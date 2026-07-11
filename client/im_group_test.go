package client

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestAPIClient_GetGroups(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/app/im/groups" {
			t.Errorf("unexpected path: %s", r.URL.Path)
		}
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(`{"groups":[{"groupId":"g1","groupName":"Team"}]}`))
	}))
	defer server.Close()

	c := NewAPIClient(&APIConfig{BaseURL: server.URL})
	resp, err := c.GetGroups(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if len(resp.Groups) != 1 || resp.Groups[0].GroupID != "g1" {
		t.Errorf("unexpected groups: %+v", resp.Groups)
	}
}

func TestAPIClient_SendGroupIM(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(`{"ok":true,"msgId":"m1"}`))
	}))
	defer server.Close()

	c := NewAPIClient(&APIConfig{BaseURL: server.URL})
	resp, err := c.SendGroupIM(context.Background(), "g1", "hi", "text")
	if err != nil {
		t.Fatal(err)
	}
	if !resp.OK || resp.MsgID != "m1" {
		t.Errorf("unexpected resp: %+v", resp)
	}
}

func TestAPIClient_RevokeMessage(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/app/im/revoke/msg_1" {
			t.Errorf("unexpected path: %s", r.URL.Path)
		}
		w.WriteHeader(http.StatusOK)
	}))
	defer server.Close()

	c := NewAPIClient(&APIConfig{BaseURL: server.URL})
	if err := c.RevokeMessage(context.Background(), "msg_1"); err != nil {
		t.Fatal(err)
	}
}

func TestAPIClient_GetBotConfig(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/app/im/bot/config" {
			t.Errorf("unexpected path: %s", r.URL.Path)
		}
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(`{"enabled":true,"persona":"helpful"}`))
	}))
	defer server.Close()

	c := NewAPIClient(&APIConfig{BaseURL: server.URL})
	resp, err := c.GetBotConfig(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if !resp.Enabled || resp.Persona != "helpful" {
		t.Errorf("unexpected config: %+v", resp)
	}
}
