package client

import (
	"context"
)

// AIConversation AI 对话摘要
type AIConversation struct {
	ConvID string `json:"convId"`
	Title  string `json:"title"`
	Model  string `json:"model,omitempty"`
}

// AIConversationsResponse 对话列表
type AIConversationsResponse struct {
	Conversations []AIConversation `json:"conversations"`
	Count         int              `json:"count,omitempty"`
}

// AIMessage AI 消息（服务端智能体返回）
type AIMessage struct {
	Role        string `json:"role"`
	Content     string `json:"content"`
	ContentType string `json:"contentType,omitempty"`
	CreatedAt   string `json:"createdAt,omitempty"`
}

// AIMessagesResponse 对话消息列表
type AIMessagesResponse struct {
	Messages []AIMessage `json:"messages"`
	Count    int         `json:"count,omitempty"`
}

// SendAIRequest 发送 AI 消息（走 qdbot_system 智能体）
type SendAIRequest struct {
	ConvID      string `json:"convId,omitempty"`
	Content     string `json:"content"`
	ContentType string `json:"contentType,omitempty"`
}

// SendAIResponse 发送 AI 响应
type SendAIResponse struct {
	ConvID   string      `json:"convId"`
	Messages []AIMessage `json:"messages,omitempty"`
	OK       bool        `json:"ok,omitempty"`
	Error    string      `json:"error,omitempty"`
}

// ListAIConversations 获取 AI 对话列表
func (c *APIClient) ListAIConversations(ctx context.Context) (*AIConversationsResponse, error) {
	var resp AIConversationsResponse
	err := c.do(ctx, "GET", "/app/ai/conversations", nil, &resp)
	return &resp, err
}

// GetAIMessages 获取 AI 对话历史
func (c *APIClient) GetAIMessages(ctx context.Context, convID string) (*AIMessagesResponse, error) {
	var resp AIMessagesResponse
	err := c.do(ctx, "GET", "/app/ai/conversations/"+convID+"/messages", nil, &resp)
	return &resp, err
}

// SendAI 向服务端 AI 智能体发送消息
func (c *APIClient) SendAI(ctx context.Context, req *SendAIRequest) (*SendAIResponse, error) {
	var resp SendAIResponse
	err := c.do(ctx, "POST", "/app/ai/send", req, &resp)
	return &resp, err
}
