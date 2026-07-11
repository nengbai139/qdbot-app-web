package client

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"time"
)

// ErrAPIError API错误
var ErrAPIError = errors.New("api error")

// APIConfig HTTP API 配置
type APIConfig struct {
	BaseURL    string // qdbot_system 基础 URL
	Token     string
	Timeout   time.Duration
}

// APIClient REST API 客户端
type APIClient struct {
	config *APIConfig
	client *http.Client
}

// NewAPIClient 创建 API 客户端
func NewAPIClient(cfg *APIConfig) *APIClient {
	if cfg == nil {
		cfg = &APIConfig{}
	}
	if cfg.Timeout == 0 {
		cfg.Timeout = 30 * time.Second
	}
	return &APIClient{
		config: cfg,
		client: &http.Client{Timeout: cfg.Timeout},
	}
}

// do 执行请求
func (c *APIClient) do(ctx context.Context, method, path string, body, result interface{}) error {
	var bodyReader io.Reader
	if body != nil {
		data, _ := json.Marshal(body)
		bodyReader = bytes.NewReader(data)
	}

	u := c.config.BaseURL + path
	req, err := http.NewRequestWithContext(ctx, method, u, bodyReader)
	if err != nil {
		return err
	}

	req.Header.Set("Content-Type", "application/json")
	if c.config.Token != "" {
		req.Header.Set("Authorization", "Bearer "+c.config.Token)
	}

	resp, err := c.client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode >= 400 {
		body, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("API error %d: %s: %w", resp.StatusCode, string(body), ErrAPIError)
	}

	if result != nil {
		return json.NewDecoder(resp.Body).Decode(result)
	}
	return nil
}

// SendIMRequest 发送 IM 消息请求
type SendIMRequest struct {
	ToUserID    string `json:"toUserId,omitempty"`
	GroupID     string `json:"groupId,omitempty"`
	Content     string `json:"content"`
	ContentType string `json:"contentType,omitempty"` // text/markdown/html
	ClientMsgID string `json:"clientMsgId,omitempty"`
}

// SendIMResponse 发送响应
type SendIMResponse struct {
	OK        bool   `json:"ok"`
	MsgID     string `json:"msgId,omitempty"`
	MessageID string `json:"messageId,omitempty"`
	Error     string `json:"error,omitempty"`
}

// SendIM 发送即时消息
func (c *APIClient) SendIM(ctx context.Context, req *SendIMRequest) (*SendIMResponse, error) {
	var resp SendIMResponse
	err := c.do(ctx, "POST", "/app/im/send", req, &resp)
	return &resp, err
}

// MessagesRequest 获取消息请求
type MessagesRequest struct {
	UserID string `json:"-"` // URL 参数
	Limit  int    `json:"-"`
	Offset int    `json:"-"`
}

// MessagesResponse 消息列表响应
type MessagesResponse struct {
	Messages []*IMMessage `json:"messages"`
	Count    int        `json:"count"`
}

// IMMessage IM 消息
type IMMessage struct {
	ID          string `json:"id"`
	FromUserID string `json:"fromUserId"`
	ToUserID   string `json:"toUserId"`
	Content    string `json:"content"`
	ContentType string `json:"contentType"`
	Status     string `json:"status"`
	CreatedAt  string `json:"createdAt"`
}

// GetMessages 获取消息历史
func (c *APIClient) GetMessages(ctx context.Context, peerID string, limit, offset int) (*MessagesResponse, error) {
	v := url.Values{"peerId": []string{peerID}}
	if limit > 0 {
		v.Set("limit", fmt.Sprintf("%d", limit))
	}
	if offset > 0 {
		v.Set("offset", fmt.Sprintf("%d", offset))
	}
	path := "/app/im/messages?" + v.Encode()

	var resp MessagesResponse
	err := c.do(ctx, "GET", path, nil, &resp)
	return &resp, err
}

// SessionsResponse 会话列表响应
type SessionsResponse struct {
	Sessions []*Session `json:"sessions"`
	Count    int       `json:"count"`
}

// Session 会话
type Session struct {
	ID        string `json:"id"`
	PeerID    string `json:"peerId"`
	PeerName  string `json:"peerName"`
	AvatarURL string `json:"avatarUrl,omitempty"`
	Unread    int    `json:"unread"`
	LastMsg   string `json:"lastMsg,omitempty"`
	LastAt    string `json:"lastAt,omitempty"`
}

// GetSessions 获取会话列表
func (c *APIClient) GetSessions(ctx context.Context) (*SessionsResponse, error) {
	var resp SessionsResponse
	err := c.do(ctx, "GET", "/app/im/sessions", nil, &resp)
	return &resp, err
}

// MarkRead 标记消息已读
func (c *APIClient) MarkRead(ctx context.Context, msgID string) error {
	req := struct {
		MsgID string `json:"msgId"`
	}{MsgID: msgID}
	return c.do(ctx, "POST", "/app/im/read", req, nil)
}

// UnreadResponse 未读数响应
type UnreadResponse struct {
	UnreadCount int    `json:"unreadCount"`
}

// GetUnreadCount 获取未读消息数
func (c *APIClient) GetUnreadCount(ctx context.Context) (*UnreadResponse, error) {
	var resp UnreadResponse
	err := c.do(ctx, "GET", "/app/im/unread", nil, &resp)
	return &resp, err
}

// GroupResponse 群组响应
type GroupResponse struct {
	GroupID   string   `json:"groupId"`
	Name      string   `json:"name"`
	AvatarURL string   `json:"avatarUrl,omitempty"`
	Members   []string `json:"members,omitempty"`
}

// CreateGroup 创建群组
func (c *APIClient) CreateGroup(ctx context.Context, name string, members []string) (*GroupResponse, error) {
	req := struct {
		Name     string   `json:"name"`
		Members  []string `json:"members"`
	}{Name: name, Members: members}
	var resp GroupResponse
	err := c.do(ctx, "POST", "/app/im/group/create", req, &resp)
	return &resp, err
}

// JoinGroup 加入群组
func (c *APIClient) JoinGroup(ctx context.Context, groupID string) error {
	return c.do(ctx, "POST", "/app/im/group/"+groupID+"/join", nil, nil)
}

// LeaveGroup 离开群组
func (c *APIClient) LeaveGroup(ctx context.Context, groupID string) error {
	return c.do(ctx, "POST", "/app/im/group/"+groupID+"/leave", nil, nil)
}

// GroupMembersResponse 群成员响应
type GroupMembersResponse struct {
	Members []string `json:"members"`
	Count  int      `json:"count"`
}

// GetGroupMembers 获取群成员
func (c *APIClient) GetGroupMembers(ctx context.Context, groupID string) (*GroupMembersResponse, error) {
	var resp GroupMembersResponse
	err := c.do(ctx, "GET", "/app/im/group/"+groupID+"/members", nil, &resp)
	return &resp, err
}

// GetGroupMessages 获取群消息
func (c *APIClient) GetGroupMessages(ctx context.Context, groupID string, limit, offset int) (*MessagesResponse, error) {
	v := url.Values{}
	if limit > 0 {
		v.Set("limit", fmt.Sprintf("%d", limit))
	}
	if offset > 0 {
		v.Set("offset", fmt.Sprintf("%d", offset))
	}
	path := "/app/im/group/" + groupID + "/messages"
	if len(v) > 0 {
		path += "?" + v.Encode()
	}
	var resp MessagesResponse
	err := c.do(ctx, "GET", path, nil, &resp)
	return &resp, err
}
