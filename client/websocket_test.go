package client

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

func TestWSConfig_Structure(t *testing.T) {
	cfg := &WSConfig{
		URL:      "ws://localhost:8080/ws",
		Token:    "test-token",
		Platform: "ios",
	}
	if cfg.URL != "ws://localhost:8080/ws" {
		t.Errorf("expected URL ws://localhost:8080/ws, got %s", cfg.URL)
	}
	if cfg.Platform != "ios" {
		t.Errorf("expected Platform ios, got %s", cfg.Platform)
	}
}

func TestNewWSClient(t *testing.T) {
	cfg := &WSConfig{
		URL:      "ws://localhost:8080/ws",
		Token:    "test-token",
		Platform: "ios",
	}
	client := NewWSClient(cfg)
	if client == nil {
		t.Fatal("NewWSClient returned nil")
	}
}

func TestNewWSClient_WithNilConfig(t *testing.T) {
	client := NewWSClient(nil)
	if client == nil {
		t.Fatal("NewWSClient returned nil with nil config")
	}
}

func TestWSClient_IsConnected(t *testing.T) {
	cfg := &WSConfig{
		URL: "ws://localhost:8080/ws",
	}
	client := NewWSClient(cfg)
	// 初始状态未连接
	if client.IsConnected() {
		t.Error("expected initially not connected")
	}
}

func TestWSClient_Close(t *testing.T) {
	cfg := &WSConfig{
		URL: "ws://localhost:8080/ws",
	}
	client := NewWSClient(cfg)
	// 关闭不应panic
	client.Close()
}

func TestWSClient_Send_NotConnected(t *testing.T) {
	cfg := &WSConfig{
		URL: "ws://localhost:8080/ws",
	}
	client := NewWSClient(cfg)

	// 未连接时发送应返回错误
	err := client.Send("message", map[string]string{"test": "data"})
	if err == nil {
		t.Error("expected error when sending while not connected")
	}
}

func TestWSMessage_JSON(t *testing.T) {
	data := `{"type":"message","data":{"msgId":"msg_123","fromId":"user_1","toId":"user_2","content":"hello"}}`

	var msg map[string]interface{}
	err := json.Unmarshal([]byte(data), &msg)
	if err != nil {
		t.Fatalf("Unmarshal failed: %v", err)
	}

	if msg["type"] != "message" {
		t.Errorf("expected Type message, got %v", msg["type"])
	}
}

func TestAppMessage_JSON_Marshal(t *testing.T) {
	msg := AppMessage{
		Type:        "message",
		MsgID:      "msg_123",
		FromID:    "user_1",
		ToID:      "user_2",
		Content:   "hello",
		ContentType: "text",
		Timestamp: 1704067200,
	}

	data, err := json.Marshal(msg)
	if err != nil {
		t.Fatalf("Marshal failed: %v", err)
	}

	var decoded AppMessage
	if err := json.Unmarshal(data, &decoded); err != nil {
		t.Fatalf("Unmarshal failed: %v", err)
	}

	if decoded.MsgID != "msg_123" {
		t.Errorf("expected MsgID msg_123, got %s", decoded.MsgID)
	}
}

func TestAppMessage_JSON_Unmarshal(t *testing.T) {
	data := []byte(`{"type":"message","msgId":"msg_456","fromId":"user_1","toId":"user_2","content":"hi","contentType":"text","timestamp":1704067200}`)

	var msg AppMessage
	err := msg.UnmarshalJSON(data)
	if err != nil {
		t.Fatalf("UnmarshalJSON failed: %v", err)
	}

	if msg.MsgID != "msg_456" {
		t.Errorf("expected MsgID msg_456, got %s", msg.MsgID)
	}
	if msg.Content != "hi" {
		t.Errorf("expected Content hi, got %s", msg.Content)
	}
}

func TestAppMessage_WithMetadata(t *testing.T) {
	data := []byte(`{"type":"message","msgId":"msg_meta","fromId":"user_1","toId":"user_2","content":"with meta","contentType":"text","timestamp":1704067200}`)

	var msg AppMessage
	err := msg.UnmarshalJSON(data)
	if err != nil {
		t.Fatalf("UnmarshalJSON failed: %v", err)
	}

	if msg.MsgID != "msg_meta" {
		t.Errorf("expected MsgID msg_meta, got %s", msg.MsgID)
	}
}

func TestAppMessage_AllContentTypes(t *testing.T) {
	types := []string{"text", "markdown", "html", "image"}

	for _, ct := range types {
		msg := AppMessage{
			Type:        "message",
			MsgID:      "msg_1",
			FromID:    "user_1",
			ToID:      "user_2",
			Content:   "test",
			ContentType: ct,
			Timestamp: time.Now().Unix(),
		}

		data, err := json.Marshal(msg)
		if err != nil {
			t.Fatalf("Marshal failed for contentType %s: %v", ct, err)
		}

		var decoded AppMessage
		if err := json.Unmarshal(data, &decoded); err != nil {
			t.Fatalf("Unmarshal failed for contentType %s: %v", ct, err)
		}

		if decoded.ContentType != ct {
			t.Errorf("expected ContentType %s, got %s", ct, decoded.ContentType)
		}
	}
}

func TestContextTimeout(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 100*time.Millisecond)
	defer cancel()

	select {
	case <-ctx.Done():
		// 预期超时
	case <-time.After(200 * time.Millisecond):
		t.Error("context should have timed out")
	}
}

func TestHTTPHandler(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "GET" {
			t.Errorf("expected GET, got %s", r.Method)
		}
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(`{"status":"ok"}`))
	}))
	defer server.Close()

	resp, err := http.Get(server.URL)
	if err != nil {
		t.Fatalf("HTTP request failed: %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != 200 {
		t.Errorf("expected status 200, got %d", resp.StatusCode)
	}
}

func TestAppMessage_EmptyContent(t *testing.T) {
	msg := AppMessage{
		Type:        "message",
		MsgID:      "msg_empty",
		FromID:    "user_1",
		ToID:      "user_2",
		Content:   "",
		ContentType: "text",
		Timestamp: time.Now().Unix(),
	}

	data, err := json.Marshal(msg)
	if err != nil {
		t.Fatalf("Marshal failed: %v", err)
	}

	var decoded AppMessage
	if err := json.Unmarshal(data, &decoded); err != nil {
		t.Fatalf("Unmarshal failed: %v", err)
	}

	if decoded.Content != "" {
		t.Errorf("expected empty content, got %s", decoded.Content)
	}
}
