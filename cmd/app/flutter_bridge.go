// Experimental Flutter bridge (frozen). See cmd/app/experimental/README.md and ADR-001.
// Product Flutter apps call qdbot_system directly; do not depend on this file.
package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"sync"
	"time"

	"qdbot_app/client"
	"qdbot_app/internal/app"
	"qdbot_app/internal/chat"
)

// FlutterMessage Flutter 消息格式
type FlutterMessage struct {
	Type    string                 `json:"type"`
	Payload map[string]interface{} `json:"payload"`
}

// FlutterBridge Flutter 桥接器
type FlutterBridge struct {
	config     *BridgeConfig
	storage    *app.FileStorage
	wsClient   *client.WSClient
	apiClient  *client.APIClient
	pushClient *client.PushClient
	chatService *chat.Service
	mu         sync.RWMutex
	onEvent    func(string, []byte)
	onMessage  func(*chat.Message)
	onConv     func(*chat.Conversation)
}

// BridgeConfig 桥接配置
type BridgeConfig struct {
	WSURL       string
	APIBaseURL  string
	Token       string
	Platform    string
	FCMKey      string
	FCMProject  string
	StoragePath string
}

// NewFlutterBridge 创建 Flutter 桥接器
func NewFlutterBridge(cfg *BridgeConfig) *FlutterBridge {
	if cfg == nil {
		cfg = &BridgeConfig{}
	}
	if cfg.StoragePath == "" {
		cfg.StoragePath = "./data"
	}
	return &FlutterBridge{
		config: cfg,
	}
}

// Init 初始化桥接器
func (b *FlutterBridge) Init() error {
	log.Println("[FlutterBridge] Initializing...")

	// 初始化存储
	storage, err := app.NewStorage(b.config.StoragePath)
	if err != nil {
		return fmt.Errorf("failed to init storage: %w", err)
	}
	b.storage = storage

	// 初始化聊天服务
	b.chatService = chat.NewService(&chat.Config{
		QDBotSystemURL: b.config.APIBaseURL,
	}, storage)

	// 初始化 API 客户端
	b.apiClient = client.NewAPIClient(&client.APIConfig{
		BaseURL: b.config.APIBaseURL,
		Token:   b.config.Token,
		Timeout: 30 * time.Second,
	})

	// 初始化 WebSocket 客户端
	wsURL := b.config.WSURL
	if wsURL == "" {
		wsURL = "ws://localhost:8080/ws"
	}

	b.wsClient = client.NewWSClient(&client.WSConfig{
		URL:      wsURL,
		Token:    b.config.Token,
		Platform: b.config.Platform,
		OnMessage: func(data []byte) {
			b.chatService.HandleMessage(data)
			// 转发到 Flutter 回调
			b.EmitEvent("ws_message", data)
		},
		OnConnect: func() {
			b.chatService.OnConnect()
			b.EmitEvent("ws_connect", nil)
		},
		OnDisconnect: func(err error) {
			b.chatService.OnDisconnect(err)
			b.EmitEvent("ws_disconnect", map[string]interface{}{"error": err.Error()})
		},
	})

	// 设置聊天服务回调
	b.chatService.SetOnMessage(func(msg *chat.Message) {
		if b.onMessage != nil {
			b.onMessage(msg)
		}
	})
	b.chatService.SetOnConversationUpdate(func(conv *chat.Conversation) {
		if b.onConv != nil {
			b.onConv(conv)
		}
	})

	// 初始化推送客户端
	b.pushClient, _ = client.NewPushClient(&client.PushConfig{
		FCMServerKey: b.config.FCMKey,
		FCMProjectID: b.config.FCMProject,
	})

	log.Println("[FlutterBridge] Initialized successfully")
	return nil
}

// Start 启动桥接器（连接 WebSocket）
func (b *FlutterBridge) Start() {
	if b.chatService != nil {
		b.chatService.Start()
	}
	if b.wsClient != nil {
		b.wsClient.Connect()
	}
}

// Stop 停止桥接器
func (b *FlutterBridge) Stop() {
	log.Println("[FlutterBridge] Stopping...")
	if b.wsClient != nil {
		b.wsClient.Close()
	}
	if b.chatService != nil {
		b.chatService.Stop()
	}
	if b.storage != nil {
		b.storage.Close()
	}
	log.Println("[FlutterBridge] Stopped")
}

// SendIM 发送即时消息
func (b *FlutterBridge) SendIM(toUserID, content string) (*chat.Message, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	// 先本地发送
	msg, err := b.chatService.SendMessage(toUserID, content, "text")
	if err != nil {
		return nil, err
	}

	// 通过 API 发送
	req := &client.SendIMRequest{
		ToUserID:    toUserID,
		Content:     content,
		ContentType: "text",
		ClientMsgID: msg.ID,
	}

	resp, err := b.apiClient.SendIM(ctx, req)
	if err != nil {
		msg.Status = chat.StatusFailed
		return msg, err
	}

	if resp.OK {
		msg.Status = chat.StatusSent
	} else {
		msg.Status = chat.StatusFailed
		return msg, fmt.Errorf("send failed: %s", resp.Error)
	}

	return msg, nil
}

// GetMessages 获取消息历史
func (b *FlutterBridge) GetMessages(peerID string, limit, offset int) ([]*chat.Message, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	// 从服务器获取
	resp, err := b.apiClient.GetMessages(ctx, peerID, limit, offset)
	if err != nil {
		// 如果服务器请求失败，从本地存储读取
		localMsgs, loadErr := b.storage.LoadMessages(peerID, limit)
		if loadErr != nil {
			return nil, err
		}

		messages := make([]*chat.Message, 0, len(localMsgs))
		for _, data := range localMsgs {
			var msg chat.Message
			if json.Unmarshal(data, &msg) == nil {
				messages = append(messages, &msg)
			}
		}
		return messages, nil
	}

	messages := make([]*chat.Message, 0, len(resp.Messages))
	for _, m := range resp.Messages {
		messages = append(messages, &chat.Message{
			ID:          m.ID,
			FromID:     m.FromUserID,
			ToID:       m.ToUserID,
			Content:     m.Content,
			ContentType: m.ContentType,
			Status:     chat.MessageStatus(m.Status),
			CreatedAt:   parseTime(m.CreatedAt),
		})
	}
	return messages, nil
}

// GetConversations 获取会话列表
func (b *FlutterBridge) GetConversations() []*chat.Conversation {
	return b.chatService.GetConversations()
}

// ChatWithAI 与 AI 智能体对话（POST /app/ai/send）
func (b *FlutterBridge) ChatWithAI(convID, prompt string) (*client.SendAIResponse, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()

	resp, err := b.apiClient.SendAI(ctx, &client.SendAIRequest{
		ConvID:      convID,
		Content:     prompt,
		ContentType: "text",
	})
	if err != nil {
		return nil, err
	}
	if resp.Error != "" {
		return resp, fmt.Errorf("ai send failed: %s", resp.Error)
	}
	return resp, nil
}

// ListAIConversations 获取 AI 对话列表
func (b *FlutterBridge) ListAIConversations() (*client.AIConversationsResponse, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	return b.apiClient.ListAIConversations(ctx)
}

// GetAIMessages 获取 AI 对话消息
func (b *FlutterBridge) GetAIMessages(convID string) (*client.AIMessagesResponse, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	return b.apiClient.GetAIMessages(ctx, convID)
}

// RegisterPushToken 注册推送令牌
func (b *FlutterBridge) RegisterPushToken(token, platform string) error {
	if b.storage != nil {
		return b.storage.SavePushToken("me", token, platform)
	}
	return fmt.Errorf("storage not initialized")
}

// SetOnMessage 设置消息回调
func (b *FlutterBridge) SetOnMessage(fn func(*chat.Message)) {
	b.onMessage = fn
}

// SetOnConversationUpdate 设置会话更新回调
func (b *FlutterBridge) SetOnConversationUpdate(fn func(*chat.Conversation)) {
	b.onConv = fn
}

// OnEvent 设置事件回调
func (b *FlutterBridge) OnEvent(fn func(event string, data []byte)) {
	b.mu.Lock()
	defer b.mu.Unlock()
	b.onEvent = fn
}

// EmitEvent 触发事件
func (b *FlutterBridge) EmitEvent(event string, data interface{}) {
	b.mu.RLock()
	fn := b.onEvent
	b.mu.RUnlock()

	if fn != nil {
		var payload []byte
		if data != nil {
			payload, _ = json.Marshal(data)
		}
		fn(event, payload)
	}
}

// PlatformInfo 获取平台信息
func (b *FlutterBridge) PlatformInfo() map[string]string {
	return map[string]string{
		"platform": b.config.Platform,
		"version":  "1.0.0",
	}
}

// IsConnected 检查 WebSocket 是否已连接
func (b *FlutterBridge) IsConnected() bool {
	if b.wsClient == nil {
		return false
	}
	return b.wsClient.IsConnected()
}

// parseTime 解析时间字符串
func parseTime(s string) time.Time {
	t, err := time.Parse(time.RFC3339, s)
	if err != nil {
		return time.Now()
	}
	return t
}
