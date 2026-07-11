package client

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

func TestNewAPIClient(t *testing.T) {
	cfg := &APIConfig{
		BaseURL: "http://localhost:8080",
		Token:   "test-token",
		Timeout: 10,
	}
	client := NewAPIClient(cfg)
	if client == nil {
		t.Fatal("NewAPIClient returned nil")
	}
	if client.config.BaseURL != "http://localhost:8080" {
		t.Errorf("expected BaseURL http://localhost:8080, got %s", client.config.BaseURL)
	}
}

func TestNewAPIClient_DefaultTimeout(t *testing.T) {
	client := NewAPIClient(nil)
	if client.config.Timeout != 30*time.Second {
		t.Errorf("expected default timeout 30s, got %v", client.config.Timeout)
	}
}

func TestAPIClient_SendIM(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "POST" {
			t.Errorf("expected POST, got %s", r.Method)
		}
		if r.URL.Path != "/app/im/send" {
			t.Errorf("expected /app/im/send, got %s", r.URL.Path)
		}
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(`{"ok":true,"messageId":"msg_123"}`))
	}))
	defer server.Close()

	client := NewAPIClient(&APIConfig{BaseURL: server.URL})
	resp, err := client.SendIM(context.Background(), &SendIMRequest{
		ToUserID:    "user_456",
		Content:     "hello",
		ContentType: "text",
	})
	if err != nil {
		t.Fatalf("SendIM failed: %v", err)
	}
	if !resp.OK {
		t.Error("expected ok=true")
	}
	if resp.MessageID != "msg_123" {
		t.Errorf("expected messageId msg_123, got %s", resp.MessageID)
	}
}

func TestAPIClient_GetMessages(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "GET" {
			t.Errorf("expected GET, got %s", r.Method)
		}
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(`{"messages":[{"id":"msg_1","fromUserId":"user_1","toUserId":"user_2","content":"hi","contentType":"text","status":"delivered","createdAt":"2024-01-01T00:00:00Z"}],"count":1}`))
	}))
	defer server.Close()

	client := NewAPIClient(&APIConfig{BaseURL: server.URL})
	resp, err := client.GetMessages(context.Background(), "user_1", 20, 0)
	if err != nil {
		t.Fatalf("GetMessages failed: %v", err)
	}
	if len(resp.Messages) != 1 {
		t.Fatalf("expected 1 message, got %d", len(resp.Messages))
	}
	if resp.Messages[0].Content != "hi" {
		t.Errorf("expected content 'hi', got %s", resp.Messages[0].Content)
	}
}

func TestAPIClient_GetUnreadCount(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "GET" {
			t.Errorf("expected GET, got %s", r.Method)
		}
		if r.URL.Path != "/app/im/unread" {
			t.Errorf("expected /app/im/unread, got %s", r.URL.Path)
		}
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(`{"unreadCount":5}`))
	}))
	defer server.Close()

	client := NewAPIClient(&APIConfig{BaseURL: server.URL})
	resp, err := client.GetUnreadCount(context.Background())
	if err != nil {
		t.Fatalf("GetUnreadCount failed: %v", err)
	}
	if resp.UnreadCount != 5 {
		t.Errorf("expected unreadCount=5, got %d", resp.UnreadCount)
	}
}

func TestAPIClient_MarkRead(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "POST" {
			t.Errorf("expected POST, got %s", r.Method)
		}
		if r.URL.Path != "/app/im/read" {
			t.Errorf("expected /app/im/read, got %s", r.URL.Path)
		}
		w.WriteHeader(http.StatusOK)
	}))
	defer server.Close()

	client := NewAPIClient(&APIConfig{BaseURL: server.URL})
	err := client.MarkRead(context.Background(), "msg_1")
	if err != nil {
		t.Fatalf("MarkRead failed: %v", err)
	}
}

func TestAPIClient_SendIM_Error(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusInternalServerError)
		w.Write([]byte("internal error"))
	}))
	defer server.Close()

	client := NewAPIClient(&APIConfig{BaseURL: server.URL})
	_, err := client.SendIM(context.Background(), &SendIMRequest{ToUserID: "user_1", Content: "hi"})
	if err == nil {
		t.Error("expected error for 500 response")
	}
}

func TestSendIMRequest_Structure(t *testing.T) {
	req := SendIMRequest{
		ToUserID:    "user_456",
		Content:     "hello",
		ContentType: "text",
		ClientMsgID: "client_msg_1",
	}
	if req.ToUserID != "user_456" {
		t.Errorf("expected ToUserID user_456, got %s", req.ToUserID)
	}
	if req.ContentType != "text" {
		t.Errorf("expected ContentType text, got %s", req.ContentType)
	}
}

func TestIMMessage_Structure(t *testing.T) {
	msg := IMMessage{
		ID:          "msg_123",
		FromUserID: "user_1",
		ToUserID:   "user_2",
		Content:    "test message",
		ContentType: "text",
		Status:     "delivered",
		CreatedAt:  "2024-01-01T00:00:00Z",
	}
	if msg.ID != "msg_123" {
		t.Errorf("expected ID msg_123, got %s", msg.ID)
	}
	if msg.Status != "delivered" {
		t.Errorf("expected Status delivered, got %s", msg.Status)
	}
}
