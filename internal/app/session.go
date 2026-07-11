package app

import (
	"context"
	"encoding/json"
	"sync"
	"time"
)

// SessionState 会话状态
type SessionState int

const (
	SessionStateDisconnected SessionState = iota
	SessionStateConnecting
	SessionStateConnected
	SessionStateReconnecting
)

// Session 会话
type Session struct {
	ID          string
	UserID      string
	DeviceID    string
	Platform    Platform
	State       SessionState
	LastActive  time.Time
	UnreadCount int
	OnStateChange func(SessionState)
	OnMessage   func(msgID, fromID, content string) // 简化消息回调
	mu          sync.RWMutex
}

// NewSession 创建新会话
func NewSession(userID, deviceID string, platform Platform) *Session {
	return &Session{
		ID:         userID + "_" + deviceID,
		UserID:     userID,
		DeviceID:   deviceID,
		Platform:  platform,
		State:     SessionStateDisconnected,
		LastActive: time.Now(),
	}
}

// SetState 设置会话状态
func (s *Session) SetState(state SessionState) {
	s.mu.Lock()
	s.State = state
	s.LastActive = time.Now()
	s.mu.Unlock()

	if s.OnStateChange != nil {
		s.OnStateChange(state)
	}
}

// HandleMessage 处理消息
func (s *Session) HandleMessage(msgID, fromID, content string) {
	s.mu.Lock()
	if fromID != s.UserID {
		s.UnreadCount++
	}
	s.LastActive = time.Now()
	s.mu.Unlock()

	if s.OnMessage != nil {
		s.OnMessage(msgID, fromID, content)
	}
}

// ResetUnread 重置未读数
func (s *Session) ResetUnread() {
	s.mu.Lock()
	s.UnreadCount = 0
	s.mu.Unlock()
}

// SessionManager 会话管理器
type SessionManager struct {
	sessions sync.Map // userID -> *Session
	storage Storage
	ctx     context.Context
	cancel  context.CancelFunc
}

// NewSessionManager 创建会话管理器
func NewSessionManager(storage Storage) *SessionManager {
	ctx, cancel := context.WithCancel(context.Background())
	return &SessionManager{
		storage: storage,
		ctx:     ctx,
		cancel:  cancel,
	}
}

// GetOrCreate 获取或创建会话
func (m *SessionManager) GetOrCreate(userID, deviceID string, platform Platform) *Session {
	key := userID

	if existing, ok := m.sessions.Load(key); ok {
		return existing.(*Session)
	}

	session := NewSession(userID, deviceID, platform)
	m.sessions.Store(key, session)

	// 从存储恢复
	if m.storage != nil {
		if stored, err := m.storage.LoadSession(userID); err == nil && len(stored) > 0 {
			var data struct {
				UnreadCount int `json:"unread_count"`
			}
			if json.Unmarshal(stored, &data) == nil {
				session.UnreadCount = data.UnreadCount
			}
		}
	}

	return session
}

// Remove 删除会话
func (m *SessionManager) Remove(userID string) {
	if session, ok := m.sessions.LoadAndDelete(userID); ok == true {
		session.(*Session).SetState(SessionStateDisconnected)
	}
}

// Start 启动管理器
func (m *SessionManager) Start() {
	go m.heartbeat()
}

// Stop 停止管理器
func (m *SessionManager) Stop() {
	m.cancel()
}

// heartbeat 心跳保活
func (m *SessionManager) heartbeat() {
	ticker := time.NewTicker(30 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-m.ctx.Done():
			return
		case <-ticker.C:
			m.persistAll()
		}
	}
}

// persistAll 持久化所有会话
func (m *SessionManager) persistAll() {
	m.sessions.Range(func(key, value any) bool {
		session := value.(*Session)
		session.mu.RLock()
		data, _ := json.Marshal(struct {
			UserID      string    `json:"user_id"`
			UnreadCount int       `json:"unread_count"`
			LastActive  time.Time `json:"last_active"`
		}{
			session.UserID,
			session.UnreadCount,
			session.LastActive,
		})
		session.mu.RUnlock()

		if m.storage != nil {
			_ = m.storage.SaveSession(session.UserID, data)
		}
		return true
	})
}

// ListSessions 列出所有会话
func (m *SessionManager) ListSessions() []*Session {
	var result []*Session
	m.sessions.Range(func(_, value any) bool {
		result = append(result, value.(*Session))
		return true
	})
	return result
}

// Count 在线会话数
func (m *SessionManager) Count() int {
	count := 0
	m.sessions.Range(func(_, _ any) bool {
		count++
		return true
	})
	return count
}
