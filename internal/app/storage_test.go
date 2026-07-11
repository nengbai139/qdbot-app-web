package app

import (
	"os"
	"path/filepath"
	"testing"
)

func TestNewStorage(t *testing.T) {
	tmpDir := t.TempDir()
	storage, err := NewStorage(tmpDir)
	if err != nil {
		t.Fatalf("NewStorage failed: %v", err)
	}
	defer storage.Close()

	// 检查目录是否创建
	sessionsDir := filepath.Join(tmpDir, "sessions")
	if _, err := os.Stat(sessionsDir); os.IsNotExist(err) {
		t.Error("sessions directory not created")
	}

	messagesDir := filepath.Join(tmpDir, "messages")
	if _, err := os.Stat(messagesDir); os.IsNotExist(err) {
		t.Error("messages directory not created")
	}

	pushTokensDir := filepath.Join(tmpDir, "push_tokens")
	if _, err := os.Stat(pushTokensDir); os.IsNotExist(err) {
		t.Error("push_tokens directory not created")
	}
}

func TestFileStorage_SaveLoadSession(t *testing.T) {
	tmpDir := t.TempDir()
	storage, err := NewStorage(tmpDir)
	if err != nil {
		t.Fatalf("NewStorage failed: %v", err)
	}
	defer storage.Close()

	data := []byte(`{"user_id":"user_123","unread_count":5}`)
	err = storage.SaveSession("user_123", data)
	if err != nil {
		t.Fatalf("SaveSession failed: %v", err)
	}

	loaded, err := storage.LoadSession("user_123")
	if err != nil {
		t.Fatalf("LoadSession failed: %v", err)
	}
	if string(loaded) != string(data) {
		t.Errorf("expected %s, got %s", string(data), string(loaded))
	}
}

func TestFileStorage_LoadSession_NotFound(t *testing.T) {
	tmpDir := t.TempDir()
	storage, err := NewStorage(tmpDir)
	if err != nil {
		t.Fatalf("NewStorage failed: %v", err)
	}
	defer storage.Close()

	_, err = storage.LoadSession("nonexistent")
	if err != ErrNotFound {
		t.Errorf("expected ErrNotFound, got %v", err)
	}
}

func TestFileStorage_DeleteSession(t *testing.T) {
	tmpDir := t.TempDir()
	storage, err := NewStorage(tmpDir)
	if err != nil {
		t.Fatalf("NewStorage failed: %v", err)
	}
	defer storage.Close()

	// 先保存
	data := []byte(`{"user_id":"user_123"}`)
	err = storage.SaveSession("user_123", data)
	if err != nil {
		t.Fatalf("SaveSession failed: %v", err)
	}

	// 再删除
	err = storage.DeleteSession("user_123")
	if err != nil {
		t.Fatalf("DeleteSession failed: %v", err)
	}

	// 验证不存在
	_, err = storage.LoadSession("user_123")
	if err != ErrNotFound {
		t.Errorf("expected ErrNotFound after delete, got %v", err)
	}
}

func TestFileStorage_SaveLoadMessage(t *testing.T) {
	tmpDir := t.TempDir()
	storage, err := NewStorage(tmpDir)
	if err != nil {
		t.Fatalf("NewStorage failed: %v", err)
	}
	defer storage.Close()

	msgData := []byte(`{"id":"msg_1","content":"hello"}`)
	err = storage.SaveMessage("user_123", "msg_1", msgData)
	if err != nil {
		t.Fatalf("SaveMessage failed: %v", err)
	}

	messages, err := storage.LoadMessages("user_123", 10)
	if err != nil {
		t.Fatalf("LoadMessages failed: %v", err)
	}
	if len(messages) != 1 {
		t.Fatalf("expected 1 message, got %d", len(messages))
	}
	if string(messages[0]) != string(msgData) {
		t.Errorf("expected %s, got %s", string(msgData), string(messages[0]))
	}
}

func TestFileStorage_LoadMessages_NotFound(t *testing.T) {
	tmpDir := t.TempDir()
	storage, err := NewStorage(tmpDir)
	if err != nil {
		t.Fatalf("NewStorage failed: %v", err)
	}
	defer storage.Close()

	messages, err := storage.LoadMessages("nonexistent_user", 10)
	if err != nil {
		t.Fatalf("LoadMessages failed: %v", err)
	}
	if len(messages) != 0 {
		t.Errorf("expected 0 messages, got %d", len(messages))
	}
}

func TestFileStorage_SaveLoadPushToken(t *testing.T) {
	tmpDir := t.TempDir()
	storage, err := NewStorage(tmpDir)
	if err != nil {
		t.Fatalf("NewStorage failed: %v", err)
	}
	defer storage.Close()

	err = storage.SavePushToken("user_123", "push_token_abc", "ios")
	if err != nil {
		t.Fatalf("SavePushToken failed: %v", err)
	}

	token, platform, err := storage.LoadPushToken("user_123")
	if err != nil {
		t.Fatalf("LoadPushToken failed: %v", err)
	}
	if token != "push_token_abc" {
		t.Errorf("expected token push_token_abc, got %s", token)
	}
	if platform != "ios" {
		t.Errorf("expected platform ios, got %s", platform)
	}
}

func TestFileStorage_LoadPushToken_NotFound(t *testing.T) {
	tmpDir := t.TempDir()
	storage, err := NewStorage(tmpDir)
	if err != nil {
		t.Fatalf("NewStorage failed: %v", err)
	}
	defer storage.Close()

	_, _, err = storage.LoadPushToken("nonexistent")
	if err != ErrNotFound {
		t.Errorf("expected ErrNotFound, got %v", err)
	}
}

func TestFileStorage_DeletePushToken(t *testing.T) {
	tmpDir := t.TempDir()
	storage, err := NewStorage(tmpDir)
	if err != nil {
		t.Fatalf("NewStorage failed: %v", err)
	}
	defer storage.Close()

	// 先保存
	err = storage.SavePushToken("user_123", "token", "android")
	if err != nil {
		t.Fatalf("SavePushToken failed: %v", err)
	}

	// 再删除
	err = storage.DeletePushToken("user_123")
	if err != nil {
		t.Fatalf("DeletePushToken failed: %v", err)
	}

	// 验证不存在
	_, _, err = storage.LoadPushToken("user_123")
	if err != ErrNotFound {
		t.Errorf("expected ErrNotFound after delete, got %v", err)
	}
}


func TestFileStorage_AuthToken(t *testing.T) {
	tmpDir := t.TempDir()
	storage, err := NewStorage(tmpDir)
	if err != nil {
		t.Fatalf("NewStorage failed: %v", err)
	}
	defer storage.Close()

	if _, err := storage.LoadAuthToken(); err != ErrNotFound {
		t.Fatalf("expected ErrNotFound, got %v", err)
	}
	if err := storage.SaveAuthToken("tok_abc"); err != nil {
		t.Fatalf("SaveAuthToken failed: %v", err)
	}
	tok, err := storage.LoadAuthToken()
	if err != nil || tok != "tok_abc" {
		t.Fatalf("LoadAuthToken = %q, %v", tok, err)
	}
	if err := storage.DeleteAuthToken(); err != nil {
		t.Fatalf("DeleteAuthToken failed: %v", err)
	}
}
