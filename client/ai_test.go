package client

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestAPIClient_SendAI(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "POST" || r.URL.Path != "/app/ai/send" {
			t.Errorf("unexpected %s %s", r.Method, r.URL.Path)
		}
		var req SendAIRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			t.Fatal(err)
		}
		if req.Content != "hello agent" {
			t.Errorf("unexpected content: %q", req.Content)
		}
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(`{"convId":"conv_1","messages":[{"role":"user","content":"hello agent"},{"role":"assistant","content":"hi"}]}`))
	}))
	defer server.Close()

	c := NewAPIClient(&APIConfig{BaseURL: server.URL})
	resp, err := c.SendAI(context.Background(), &SendAIRequest{Content: "hello agent", ContentType: "text"})
	if err != nil {
		t.Fatalf("SendAI failed: %v", err)
	}
	if resp.ConvID != "conv_1" {
		t.Errorf("expected conv_1, got %s", resp.ConvID)
	}
	if len(resp.Messages) != 2 || resp.Messages[1].Role != "assistant" {
		t.Errorf("unexpected messages: %+v", resp.Messages)
	}
}

func TestAPIClient_ListAIConversations(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/app/ai/conversations" {
			t.Errorf("unexpected path: %s", r.URL.Path)
		}
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(`{"conversations":[{"convId":"c1","title":"Test","model":"agent"}]}`))
	}))
	defer server.Close()

	c := NewAPIClient(&APIConfig{BaseURL: server.URL})
	resp, err := c.ListAIConversations(context.Background())
	if err != nil {
		t.Fatalf("ListAIConversations failed: %v", err)
	}
	if len(resp.Conversations) != 1 || resp.Conversations[0].ConvID != "c1" {
		t.Errorf("unexpected conversations: %+v", resp.Conversations)
	}
}

func TestAPIClient_GetAIMessages(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/app/ai/conversations/conv_1/messages" {
			t.Errorf("unexpected path: %s", r.URL.Path)
		}
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(`{"messages":[{"role":"assistant","content":"ok"}]}`))
	}))
	defer server.Close()

	c := NewAPIClient(&APIConfig{BaseURL: server.URL})
	resp, err := c.GetAIMessages(context.Background(), "conv_1")
	if err != nil {
		t.Fatalf("GetAIMessages failed: %v", err)
	}
	if len(resp.Messages) != 1 || resp.Messages[0].Content != "ok" {
		t.Errorf("unexpected messages: %+v", resp.Messages)
	}
}
