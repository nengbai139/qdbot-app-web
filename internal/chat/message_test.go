package chat

import (
	"encoding/json"
	"testing"
)

func TestNewService(t *testing.T) {
	cfg := &Config{
		QDBotSystemURL: "http://localhost:8080",
		APIVersion:    "v1",
	}
	svc := NewService(cfg, nil)
	if svc == nil {
		t.Fatal("NewService returned nil")
	}
	if svc.config.QDBotSystemURL != "http://localhost:8080" {
		t.Errorf("expected URL http://localhost:8080, got %s", svc.config.QDBotSystemURL)
	}
}

func TestNewService_DefaultAPIVersion(t *testing.T) {
	cfg := &Config{}
	svc := NewService(cfg, nil)
	if svc.config.APIVersion != "v1" {
		t.Errorf("expected default APIVersion v1, got %s", svc.config.APIVersion)
	}
}

func TestNewService_NilConfig(t *testing.T) {
	svc := NewService(nil, nil)
	if svc == nil {
		t.Fatal("NewService returned nil with nil config")
	}
}

func TestService_StartStop(t *testing.T) {
	svc := NewService(nil, nil)
	svc.Start()
	svc.Stop()
}

func TestMessage_Structure(t *testing.T) {
	msg := Message{
		ID:          "msg_123",
		FromID:     "user_1",
		ToID:       "user_2",
		Content:    "hello",
		ContentType: "text",
		Type:       "user",
		Status:     StatusSending,
	}

	if msg.ID != "msg_123" {
		t.Errorf("expected ID msg_123, got %s", msg.ID)
	}
	if msg.ContentType != "text" {
		t.Errorf("expected ContentType text, got %s", msg.ContentType)
	}
	if msg.Status != StatusSending {
		t.Errorf("expected StatusSending, got %s", msg.Status)
	}
}

func TestAppMessage_Structure(t *testing.T) {
	msg := AppMessage{
		Type:        "message",
		MsgID:      "msg_456",
		FromID:    "user_1",
		ToID:      "user_2",
		Content:   "hi",
		ContentType: "text",
		Timestamp: 1704067200,
	}

	if msg.Type != "message" {
		t.Errorf("expected Type message, got %s", msg.Type)
	}
	if msg.Timestamp != 1704067200 {
		t.Errorf("expected Timestamp 1704067200, got %d", msg.Timestamp)
	}
}

func TestAppMessage_JSON(t *testing.T) {
	data := `{"type":"message","msgId":"msg_123","fromId":"user_1","toId":"user_2","content":"hello","contentType":"text","timestamp":1704067200}`

	var msg AppMessage
	err := json.Unmarshal([]byte(data), &msg)
	if err != nil {
		t.Fatalf("Unmarshal failed: %v", err)
	}

	if msg.MsgID != "msg_123" {
		t.Errorf("expected MsgID msg_123, got %s", msg.MsgID)
	}
	if msg.Content != "hello" {
		t.Errorf("expected Content hello, got %s", msg.Content)
	}
}

func TestConversation_Structure(t *testing.T) {
	conv := Conversation{
		ID:        "conv_123",
		Type:      ConvTypeSingle,
		PeerID:   "user_456",
		PeerName: "John",
		Unread:   3,
	}

	if conv.Type != ConvTypeSingle {
		t.Errorf("expected ConvTypeSingle, got %s", conv.Type)
	}
	if conv.Unread != 3 {
		t.Errorf("expected Unread 3, got %d", conv.Unread)
	}
}

func TestConvType_Constants(t *testing.T) {
	if ConvTypeSingle != "single" {
		t.Errorf("expected ConvTypeSingle=single, got %s", ConvTypeSingle)
	}
	if ConvTypeGroup != "group" {
		t.Errorf("expected ConvTypeGroup=group, got %s", ConvTypeGroup)
	}
	if ConvTypeAI != "ai" {
		t.Errorf("expected ConvTypeAI=ai, got %s", ConvTypeAI)
	}
}

func TestMessageStatus_Constants(t *testing.T) {
	if StatusSending != "sending" {
		t.Errorf("expected StatusSending=sending, got %s", StatusSending)
	}
	if StatusSent != "sent" {
		t.Errorf("expected StatusSent=sent, got %s", StatusSent)
	}
	if StatusDelivered != "delivered" {
		t.Errorf("expected StatusDelivered=delivered, got %s", StatusDelivered)
	}
	if StatusRead != "read" {
		t.Errorf("expected StatusRead=read, got %s", StatusRead)
	}
	if StatusFailed != "failed" {
		t.Errorf("expected StatusFailed=failed, got %s", StatusFailed)
	}
}

func TestService_HandleMessage(t *testing.T) {
	svc := NewService(nil, nil)
	var receivedMsg *Message
	svc.SetOnMessage(func(msg *Message) {
		receivedMsg = msg
	})

	data := []byte(`{"type":"message","msgId":"msg_789","fromId":"user_1","toId":"user_2","content":"test","contentType":"text","timestamp":1704067200}`)
	svc.HandleMessage(data)

	if receivedMsg == nil {
		t.Fatal("onMessage callback was not called")
	}
	if receivedMsg.ID != "msg_789" {
		t.Errorf("expected ID msg_789, got %s", receivedMsg.ID)
	}
}

func TestService_HandleMessage_InvalidJSON(t *testing.T) {
	svc := NewService(nil, nil)
	var called bool
	svc.SetOnMessage(func(msg *Message) {
		called = true
	})

	// 无效 JSON 不应触发回调
	svc.HandleMessage([]byte(`invalid json`))
	if called {
		t.Error("onMessage should not be called for invalid JSON")
	}
}

func TestService_GetConversations(t *testing.T) {
	svc := NewService(nil, nil)
	convs := svc.GetConversations()
	if convs == nil {
		t.Error("GetConversations returned nil")
	}
	if len(convs) != 0 {
		t.Errorf("expected 0 conversations, got %d", len(convs))
	}
}

func TestService_OnConnect_OnDisconnect(t *testing.T) {
	svc := NewService(nil, nil)
	svc.OnConnect()
	svc.OnDisconnect(nil)
}

func TestTruncateContent(t *testing.T) {
	tests := []struct {
		input    string
		maxLen   int
		expected string
	}{
		{"hello", 10, "hello"},
		{"hello world", 5, "hello..."},
		{"hi", 10, "hi"},
		{"", 5, ""},
	}

	for _, tt := range tests {
		result := truncateContent(tt.input, tt.maxLen)
		if result != tt.expected {
			t.Errorf("truncateContent(%q, %d): expected %q, got %q", tt.input, tt.maxLen, tt.expected, result)
		}
	}
}

func TestGenerateMsgID(t *testing.T) {
	id1 := generateMsgID()
	id2 := generateMsgID()

	if id1 == "" {
		t.Error("generateMsgID returned empty string")
	}
	if id1 == id2 {
		t.Error("generateMsgID returned same ID twice")
	}
	if len(id1) < 4 || id1[:4] != "msg_" {
		t.Errorf("expected ID to start with msg_, got %s", id1)
	}
}
