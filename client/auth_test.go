package client

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestAPIClient_Login(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/app/auth/login" {
			t.Errorf("unexpected path: %s", r.URL.Path)
		}
		var req LoginRequest
		_ = json.NewDecoder(r.Body).Decode(&req)
		if req.Email != "a@b.com" {
			t.Errorf("unexpected email: %s", req.Email)
		}
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(`{"token":"tok_1","userId":"u1","userCode":"UC001"}`))
	}))
	defer server.Close()

	c := NewAPIClient(&APIConfig{BaseURL: server.URL})
	resp, err := c.Login(context.Background(), &LoginRequest{
		Email: "a@b.com", Password: "secret", DeviceID: "d1", Platform: "ios",
	})
	if err != nil {
		t.Fatal(err)
	}
	if resp.Token != "tok_1" || resp.UserID != "u1" {
		t.Errorf("unexpected resp: %+v", resp)
	}
}

func TestAPIClient_SendVerificationCode(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/app/auth/verification/send-code" {
			t.Errorf("unexpected path: %s", r.URL.Path)
		}
		w.WriteHeader(http.StatusOK)
	}))
	defer server.Close()

	c := NewAPIClient(&APIConfig{BaseURL: server.URL})
	err := c.SendVerificationCode(context.Background(), &SendCodeRequest{Email: "a@b.com", Purpose: "login"})
	if err != nil {
		t.Fatal(err)
	}
}
