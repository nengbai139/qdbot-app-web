package client

import (
	"context"
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"net/url"
	"sync"
	"time"

	"github.com/gorilla/websocket"
)

const (
	// pongWait is the time allowed to read the next pong message from the server.
	pongWait = 60 * time.Second
	// pingPeriod is the period at which ping messages are sent to the server.
	// Must be less than pongWait.
	pingPeriod = 20 * time.Second
	// writeWait is the time allowed to write a message to the server.
	writeWait = 10 * time.Second
)

// ErrDisconnected 连接断开
var ErrDisconnected = errors.New("disconnected")

// WSClientInterface WebSocket客户端接口 (用于测试mock)
type WSClientInterface interface {
	Connect() error
	Close() error
	Send(msgType string, data interface{}) error
	IsConnected() bool
}

// MockWSClient Mock WebSocket客户端 (用于测试)
type MockWSClient struct {
	Connected   bool
	Messages    []WsMessage
	OnMessage   func([]byte)
	OnConnect   func()
	OnDisconnect func(err error)
}

// Connect 模拟连接
func (m *MockWSClient) Connect() error {
	m.Connected = true
	if m.OnConnect != nil {
		m.OnConnect()
	}
	return nil
}

// Close 模拟关闭
func (m *MockWSClient) Close() error {
	m.Connected = false
	if m.OnDisconnect != nil {
		m.OnDisconnect(nil)
	}
	return nil
}

// Send 模拟发送消息
func (m *MockWSClient) Send(msgType string, data interface{}) error {
	if !m.Connected {
		return ErrDisconnected
	}
	m.Messages = append(m.Messages, WsMessage{Type: msgType, Data: data})
	return nil
}

// IsConnected 返回连接状态
func (m *MockWSClient) IsConnected() bool {
	return m.Connected
}

// WConfig WebSocket 配置
type WSConfig struct {
	URL           string
	Token        string
	Platform     string
	OnMessage    func([]byte)    // 收到消息回调
	OnConnect    func()          // 连接成功回调
	OnDisconnect func(err error) // 断开回调
	OnError      func(error)    // 错误回调
}

// WSClient WebSocket 客户端
type WSClient struct {
	config    *WSConfig
	conn      *websocket.Conn
	mu        sync.RWMutex
	done      chan struct{}
	wg        sync.WaitGroup
	closeOnce sync.Once  // 确保 cleanup 只触发一次 OnDisconnect
	reconnMu  sync.Mutex // 防止并发 Connect
}

// NewWSClient 创建 WebSocket 客户端
func NewWSClient(config *WSConfig) *WSClient {
	return &WSClient{
		config: config,
		done:  make(chan struct{}),
	}
}

// Connect 连接 WebSocket（并发安全，多次调用不会创建重复连接）
func (c *WSClient) Connect() error {
	// 防止并发 Connect
	c.reconnMu.Lock()
	defer c.reconnMu.Unlock()

	// 如果已经连接，不重复连接
	if c.IsConnected() {
		return nil
	}

	u, err := url.Parse(c.config.URL)
	if err != nil {
		return err
	}

	// 添加认证参数
	q := u.Query()
	q.Set("token", c.config.Token)
	q.Set("platform", c.config.Platform)
	u.RawQuery = q.Encode()

	header := http.Header{}
	header.Set("X-Platform", c.config.Platform)
	header.Set("Authorization", "Bearer "+c.config.Token)

	conn, resp, err := websocket.DefaultDialer.Dial(u.String(), header)
	if err != nil {
		if resp != nil {
			resp.Body.Close()
		}
		return err
	}

	// 设置 Pong 处理器 — 收到服务端 pong 时刷新读超时
	conn.SetPongHandler(func(string) error {
		conn.SetReadDeadline(time.Now().Add(pongWait))
		return nil
	})

	// 重置 closeOnce，允许新一轮的 cleanup
	c.closeOnce = sync.Once{}

	c.mu.Lock()
	c.conn = conn
	c.mu.Unlock()

	// 启动读写 goroutine
	c.wg.Add(2)
	go c.readLoop()
	go c.pingLoop()

	if c.config.OnConnect != nil {
		c.config.OnConnect()
	}

	log.Printf("[ws] Connected to %s", u.Host)
	return nil
}

// Close 关闭连接
func (c *WSClient) Close() error {
	close(c.done)
	c.wg.Wait()

	c.mu.Lock()
	defer c.mu.Unlock()

	if c.conn == nil {
		return nil
	}

	err := c.conn.Close()
	c.conn = nil
	return err
}

// Send 发送消息
func (c *WSClient) Send(msgType string, data interface{}) error {
	c.mu.RLock()
	conn := c.conn
	c.mu.RUnlock()

	if conn == nil {
		return ErrDisconnected
	}

	// 设置写超时，防止 TCP 半开连接时永久阻塞
	conn.SetWriteDeadline(time.Now().Add(writeWait))
	msg := WsMessage{
		Type: msgType,
		Data: data,
	}
	return conn.WriteJSON(msg)
}

// readLoop 读取循环
func (c *WSClient) readLoop() {
	defer c.wg.Done()

	for {
		select {
		case <-c.done:
			return
		default:
		}

		c.mu.RLock()
		conn := c.conn
		c.mu.RUnlock()

		if conn == nil {
			return
		}

		// 设置读超时：pongWait 内必须收到下一条消息（或 pong）
		conn.SetReadDeadline(time.Now().Add(pongWait))
		_, msg, err := conn.ReadMessage()
		if err != nil {
			// 检查是否已经通过 done 信号退出
			select {
			case <-c.done:
				return
			default:
			}

			if !errors.Is(err, websocket.ErrCloseSent) {
				log.Printf("[ws] Read error: %v", err)
				if c.config.OnError != nil {
					c.config.OnError(err)
				}
			}
			c.cleanup()
			return
		}

		if c.config.OnMessage != nil {
			c.config.OnMessage(msg)
		}
	}
}

// pingLoop 心跳循环 — 客户端主动发 ping 给服务端
func (c *WSClient) pingLoop() {
	defer c.wg.Done()

	ticker := time.NewTicker(pingPeriod)
	defer ticker.Stop()

	for {
		select {
		case <-c.done:
			return
		case <-ticker.C:
			c.mu.RLock()
			conn := c.conn
			c.mu.RUnlock()

			if conn == nil {
				return
			}

			// 写超时短于 ping 间隔，避免堆积
			if err := conn.WriteControl(websocket.PingMessage, nil, time.Now().Add(writeWait)); err != nil {
				log.Printf("[ws] Ping error: %v", err)
				c.cleanup()
				return
			}
		}
	}
}

// cleanup 清理连接 — 使用 sync.Once 确保 OnDisconnect 只触发一次
func (c *WSClient) cleanup() {
	c.closeOnce.Do(func() {
		c.mu.Lock()
		if c.conn != nil {
			c.conn.Close()
			c.conn = nil
		}
		c.mu.Unlock()

		if c.config.OnDisconnect != nil {
			c.config.OnDisconnect(nil)
		}
	})
}

// IsConnected 是否已连接
func (c *WSClient) IsConnected() bool {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.conn != nil
}

// WsMessage WebSocket 消息格式
type WsMessage struct {
	Type string      `json:"type"`
	Data interface{} `json:"data"`
}

// PingMessage Ping 消息
type PingMessage struct {
	Type    string `json:"type"`
	Content string `json:"content"`
}

// PongMessage Pong 响应
type PongMessage struct {
	Type    string `json:"type"`
	Content string `json:"content"`
}

// AppMessage App 消息
type AppMessage struct {
	Type        string `json:"type"`
	MsgID       string `json:"msgId"`
	FromID     string `json:"fromId"`
	ToID       string `json:"toId"`
	Content     string `json:"content"`
	ContentType string `json:"contentType"`
	Timestamp   int64  `json:"timestamp"`
}

// MarshalJSON 实现 json.Marshaler
func (m *AppMessage) MarshalJSON() ([]byte, error) {
	return json.Marshal(m)
}

// UnmarshalJSON 实现 json.Unmarshaler
func (m *AppMessage) UnmarshalJSON(data []byte) error {
	type msg struct {
		Type        string `json:"type"`
		MsgID       string `json:"msgId"`
		FromID     string `json:"fromId"`
		ToID       string `json:"toId"`
		Content     string `json:"content"`
		ContentType string `json:"contentType"`
		Timestamp   int64  `json:"timestamp"`
	}
	var m2 msg
	if err := json.Unmarshal(data, &m2); err != nil {
		return err
	}
	m.Type = m2.Type
	m.MsgID = m2.MsgID
	m.FromID = m2.FromID
	m.ToID = m2.ToID
	m.Content = m2.Content
	m.ContentType = m2.ContentType
	m.Timestamp = m2.Timestamp
	return nil
}

// ReconnectContext 重连上下文
type ReconnectContext struct {
	client *WSClient
	maxRetries int
	backoff    time.Duration
}

// NewReconnectContext 创建重连上下文
func NewReconnectContext(client *WSClient) *ReconnectContext {
	return &ReconnectContext{
		client:    client,
		maxRetries: 10,
		backoff:   time.Second,
	}
}

// Do 重连直到成功或超时
func (ctx *ReconnectContext) Do(timeout time.Duration) error {
	deadline := time.Now().Add(timeout)

	for i := 0; i < ctx.maxRetries; i++ {
		if time.Now().After(deadline) {
			return context.DeadlineExceeded
		}

		log.Printf("[ws] Reconnecting (attempt %d/%d)...", i+1, ctx.maxRetries)

		if err := ctx.client.Connect(); err == nil {
			return nil
		}

		// 指数退避
		backoff := ctx.backoff * time.Duration(1<<uint(i))
		if backoff > 30*time.Second {
			backoff = 30 * time.Second
		}

		select {
		case <-time.After(backoff):
		case <-ctx.client.done:
			return context.Canceled
		}
	}

	return errors.New("max retries exceeded")
}
