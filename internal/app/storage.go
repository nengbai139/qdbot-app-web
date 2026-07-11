package app

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"sync"
)

// ErrNotFound 未找到
var ErrNotFound = errors.New("not found")

// Storage 接口
type Storage interface {
	// 会话
	SaveSession(userID string, data []byte) error
	LoadSession(userID string) ([]byte, error)
	DeleteSession(userID string) error

	// 消息
	SaveMessage(userID, msgID string, data []byte) error
	LoadMessages(userID string, limit int) ([][]byte, error)
	DeleteMessage(msgID string) error

	// 推送令牌
	SavePushToken(userID, token string, platform string) error
	LoadPushToken(userID string) (token, platform string, err error)
	DeletePushToken(userID string) error

	// 认证令牌
	SaveAuthToken(token string) error
	LoadAuthToken() (string, error)
	DeleteAuthToken() error

	// 关闭
	Close() error
}

// FileStorage 基于文件的存储
type FileStorage struct {
	baseDir string
	mu     sync.RWMutex
}

// NewStorage 创建文件存储
func NewStorage(basePath string) (*FileStorage, error) {
	if err := os.MkdirAll(basePath, 0755); err != nil {
		return nil, err
	}

	// 创建子目录
	dirs := []string{"sessions", "messages", "push_tokens"}
	for _, dir := range dirs {
		if err := os.MkdirAll(filepath.Join(basePath, dir), 0755); err != nil {
			return nil, err
		}
	}

	return &FileStorage{baseDir: basePath}, nil
}

func (s *FileStorage) sessionsDir() string  { return filepath.Join(s.baseDir, "sessions") }
func (s *FileStorage) messagesDir() string { return filepath.Join(s.baseDir, "messages") }
func (s *FileStorage) pushTokensDir() string { return filepath.Join(s.baseDir, "push_tokens") }

// SaveSession 保存会话
func (s *FileStorage) SaveSession(userID string, data []byte) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	return os.WriteFile(filepath.Join(s.sessionsDir(), userID+".json"), data, 0644)
}

// LoadSession 加载会话
func (s *FileStorage) LoadSession(userID string) ([]byte, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	data, err := os.ReadFile(filepath.Join(s.sessionsDir(), userID+".json"))
	if os.IsNotExist(err) {
		return nil, ErrNotFound
	}
	return data, err
}

// DeleteSession 删除会话
func (s *FileStorage) DeleteSession(userID string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	err := os.Remove(filepath.Join(s.sessionsDir(), userID+".json"))
	if os.IsNotExist(err) {
		return nil
	}
	return err
}

// SaveMessage 保存消息
func (s *FileStorage) SaveMessage(userID, msgID string, data []byte) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	dir := filepath.Join(s.messagesDir(), userID)
	if err := os.MkdirAll(dir, 0755); err != nil {
		return err
	}
	return os.WriteFile(filepath.Join(dir, msgID+".json"), data, 0644)
}

// LoadMessages 加载消息
func (s *FileStorage) LoadMessages(userID string, limit int) ([][]byte, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	dir := filepath.Join(s.messagesDir(), userID)

	entries, err := os.ReadDir(dir)
	if os.IsNotExist(err) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}

	var files []string
	for _, e := range entries {
		if !e.IsDir() {
			files = append(files, e.Name())
		}
	}

	// 倒序（最新在前）
	reverse(files)

	if limit > 0 && len(files) > limit {
		files = files[:limit]
	}

	result := make([][]byte, 0, len(files))
	for _, f := range files {
		data, _ := os.ReadFile(filepath.Join(dir, f))
		result = append(result, data)
	}

	return result, nil
}

// DeleteMessage 删除消息
func (s *FileStorage) DeleteMessage(msgID string) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	// 遍历所有用户目录查找并删除
	entries, _ := os.ReadDir(s.messagesDir())
	for _, e := range entries {
		if e.IsDir() {
			path := filepath.Join(s.messagesDir(), e.Name(), msgID+".json")
			if _, err := os.Stat(path); err == nil {
				return os.Remove(path)
			}
		}
	}
	return ErrNotFound
}

// SavePushToken 保存推送令牌
func (s *FileStorage) SavePushToken(userID, token, platform string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	data, _ := json.Marshal(struct {
		Token    string `json:"token"`
		Platform string `json:"platform"`
	}{Token: token, Platform: platform})
	return os.WriteFile(filepath.Join(s.pushTokensDir(), userID+".json"), data, 0644)
}

// LoadPushToken 加载推送令牌
func (s *FileStorage) LoadPushToken(userID string) (token, platform string, err error) {
	s.mu.RLock()
	data, err := os.ReadFile(filepath.Join(s.pushTokensDir(), userID+".json"))
	s.mu.RUnlock()
	if os.IsNotExist(err) {
		return "", "", ErrNotFound
	}
	if err != nil {
		return "", "", err
	}
	var rec struct {
		Token    string `json:"token"`
		Platform string `json:"platform"`
	}
	if err := json.Unmarshal(data, &rec); err != nil {
		return "", "", err
	}
	return rec.Token, rec.Platform, nil
}

// DeletePushToken 删除推送令牌
func (s *FileStorage) DeletePushToken(userID string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	err := os.Remove(filepath.Join(s.pushTokensDir(), userID+".json"))
	if os.IsNotExist(err) {
		return nil
	}
	return err
}

func (s *FileStorage) authTokenPath() string { return filepath.Join(s.baseDir, "auth_token.json") }

// SaveAuthToken 保存登录 token
func (s *FileStorage) SaveAuthToken(token string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	return os.WriteFile(s.authTokenPath(), []byte(token), 0600)
}

// LoadAuthToken 加载登录 token
func (s *FileStorage) LoadAuthToken() (string, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	data, err := os.ReadFile(s.authTokenPath())
	if os.IsNotExist(err) {
		return "", ErrNotFound
	}
	if err != nil {
		return "", err
	}
	if len(data) == 0 {
		return "", ErrNotFound
	}
	return string(data), nil
}

// DeleteAuthToken 删除登录 token
func (s *FileStorage) DeleteAuthToken() error {
	s.mu.Lock()
	defer s.mu.Unlock()
	err := os.Remove(s.authTokenPath())
	if os.IsNotExist(err) {
		return nil
	}
	return err
}

// Close 关闭存储
func (s *FileStorage) Close() error {
	return nil // 无需关闭
}

// reverse 原地反转字符串切片
func reverse(ss []string) {
	for i, j := 0, len(ss)-1; i < j; i, j = i+1, j-1 {
		ss[i], ss[j] = ss[j], ss[i]
	}
}
