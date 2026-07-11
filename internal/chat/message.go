package chat

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"sync"
	"time"

	"qdbot_app/client"
)

// Storage 消息存储接口 (避免循环导入)
type Storage interface {
	SaveMessage(userID, msgID string, data []byte) error
	LoadMessages(userID string, limit int) ([][]byte, error)
}

// Message 聊天消息
type Message struct {
	ID          string       `json:"id"`
	FromID     string       `json:"from_id"`
	ToID       string       `json:"to_id"`
	Content    string       `json:"content"`
	ContentType string       `json:"content_type"` // text/markdown/html/image
	Type        string       `json:"type"`        // user/bot/system
	Status     MessageStatus `json:"status"`      // sending/sent/delivered/read
	CreatedAt  time.Time    `json:"created_at"`
	Metadata   map[string]interface{} `json:"metadata,omitempty"`
}

// AppMessage App 入站消息 (来自 WebSocket)
type AppMessage struct {
	Type       string `json:"type"`
	MsgID      string `json:"msgId"`
	FromID    string `json:"fromId"`
	ToID      string `json:"toId"`
	Content   string `json:"content"`
	ContentType string `json:"contentType"`
	Timestamp int64  `json:"timestamp"`
}

// MessageStatus 消息状态
type MessageStatus string

const (
	StatusSending   MessageStatus = "sending"
	StatusSent     MessageStatus = "sent"
	StatusDelivered MessageStatus = "delivered"
	StatusRead     MessageStatus = "read"
	StatusFailed   MessageStatus = "failed"
)

// Conversation 会话
type Conversation struct {
	ID         string    `json:"id"`
	Type       ConvType  `json:"type"` // single/group/ai
	PeerID     string    `json:"peer_id"`
	PeerName   string    `json:"peer_name"`
	PeerAvatar string    `json:"peer_avatar,omitempty"`
	LastMsg    string    `json:"last_msg,omitempty"`
	LastMsgAt  time.Time `json:"last_msg_at,omitempty"`
	Unread     int      `json:"unread"`
}

// ConvType 会话类型
type ConvType string

const (
	ConvTypeSingle ConvType = "single"
	ConvTypeGroup  ConvType = "group"
	ConvTypeAI     ConvType = "ai"
)

// Service 聊天服务
type Service struct {
	config        *Config
	apiClient     *client.APIClient
	sessionMgr    interface{} // 避免循环导入
	storage       Storage
	conversations map[string]*Conversation
	mu            sync.RWMutex
	onMessage     func(*Message)
	onConvUpdate  func(*Conversation)
}

// Config 配置
type Config struct {
	QDBotSystemURL string
	APIVersion    string
}

// NewService 创建聊天服务
func NewService(config *Config, storage Storage) *Service {
	if config == nil {
		config = &Config{}
	}
	if config.APIVersion == "" {
		config.APIVersion = "v1"
	}
	return &Service{
		config:     config,
		storage:    storage,
		conversations: make(map[string]*Conversation),
	}
}

// SetAPIClient 设置 REST 客户端（发送消息走 /app/im/send）
func (s *Service) SetAPIClient(c *client.APIClient) {
	s.apiClient = c
}

// Start 启动服务
func (s *Service) Start() {
	log.Printf("[chat] Service started, qdbot_system: %s", s.config.QDBotSystemURL)
}

// Stop 停止服务
func (s *Service) Stop() {
	log.Println("[chat] Service stopped")
}

// HandleMessage 处理收到的消息
func (s *Service) HandleMessage(data []byte) {
	var msg AppMessage
	if err := json.Unmarshal(data, &msg); err != nil {
		log.Printf("[chat] Unmarshal error: %v", err)
		return
	}

	message := &Message{
		ID:          msg.MsgID,
		FromID:     msg.FromID,
		ToID:       msg.ToID,
		Content:     msg.Content,
		ContentType: msg.ContentType,
		Type:        "user",
		Status:     StatusDelivered,
		CreatedAt:   time.Now(),
	}

	// 更新会话
	s.updateConversation(message)

	// 触发回调
	if s.onMessage != nil {
		s.onMessage(message)
	}
}

// SendMessage 发送消息
func (s *Service) SendMessage(toID, content, contentType string) (*Message, error) {
	msg := &Message{
		ID:          generateMsgID(),
		FromID:     "me",
		ToID:       toID,
		Content:     content,
		ContentType: contentType,
		Type:        "user",
		Status:     StatusSending,
		CreatedAt:   time.Now(),
	}

	s.saveMessage(msg)
	s.updateConversation(msg)

	if s.apiClient == nil {
		return msg, nil
	}

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	resp, err := s.apiClient.SendIM(ctx, &client.SendIMRequest{
		ToUserID:    toID,
		Content:     content,
		ContentType: contentType,
		ClientMsgID: msg.ID,
	})
	if err != nil {
		msg.Status = StatusFailed
		return msg, err
	}
	if !resp.OK {
		msg.Status = StatusFailed
		return msg, fmt.Errorf("send failed: %s", resp.Error)
	}
	msg.Status = StatusSent
	id := resp.MsgID
	if id == "" {
		id = resp.MessageID
	}
	if id != "" {
		msg.ID = id
	}
	return msg, nil
}

// SetOnMessage 设置消息回调
func (s *Service) SetOnMessage(fn func(*Message)) {
	s.onMessage = fn
}

// SetOnConversationUpdate 设置会话更新回调
func (s *Service) SetOnConversationUpdate(fn func(*Conversation)) {
	s.onConvUpdate = fn
}

// updateConversation 更新会话
func (s *Service) updateConversation(msg *Message) {
	s.mu.Lock()
	defer s.mu.Unlock()

	peerID := msg.ToID
	if msg.Type == "user" {
		peerID = msg.FromID
	}

	conv, ok := s.conversations[peerID]
	if !ok {
		conv = &Conversation{
			ID:     peerID,
			Type:   ConvTypeSingle,
			PeerID: peerID,
		}
		s.conversations[peerID] = conv
	}

	conv.LastMsg = truncateContent(msg.Content, 50)
	conv.LastMsgAt = msg.CreatedAt

	if msg.Type == "user" && msg.FromID != "me" {
		conv.Unread++
	}

	if s.onConvUpdate != nil {
		go s.onConvUpdate(conv)
	}
}

// saveMessage 保存消息到本地
func (s *Service) saveMessage(msg *Message) {
	if s.storage == nil {
		return
	}

	data, _ := json.Marshal(msg)
	_ = s.storage.SaveMessage(msg.ToID, msg.ID, data)
}

// GetConversations 获取会话列表
func (s *Service) GetConversations() []*Conversation {
	s.mu.RLock()
	defer s.mu.RUnlock()

	result := make([]*Conversation, 0, len(s.conversations))
	for _, c := range s.conversations {
		result = append(result, c)
	}
	return result
}

// OnConnect 连接成功回调
func (s *Service) OnConnect() {
	log.Println("[chat] Connected")
}

// OnDisconnect 断开连接回调
func (s *Service) OnDisconnect(err error) {
	log.Printf("[chat] Disconnected: %v", err)
}

// truncateContent 截断内容
func truncateContent(s string, maxLen int) string {
	runes := []rune(s)
	if len(runes) > maxLen {
		return string(runes[:maxLen]) + "..."
	}
	return s
}

// generateMsgID 生成消息 ID
func generateMsgID() string {
	return fmt.Sprintf("msg_%d", time.Now().UnixNano())
}
