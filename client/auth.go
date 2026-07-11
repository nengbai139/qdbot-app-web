package client

import "context"

// LoginRequest 登录请求
type LoginRequest struct {
	Email    string `json:"email"`
	Password string `json:"password"`
	DeviceID string `json:"deviceId"`
	Platform string `json:"platform"`
}

// LoginResponse 登录响应
type LoginResponse struct {
	Token    string `json:"token"`
	UserID   string `json:"userId"`
	UserCode string `json:"userCode,omitempty"`
	Error    string `json:"error,omitempty"`
}

// SendCodeRequest 验证码请求
type SendCodeRequest struct {
	Email   string `json:"email"`
	Purpose string `json:"purpose"` // login | register
}

// RegisterRequest 注册请求
type RegisterRequest struct {
	Username   string `json:"username"`
	Email      string `json:"email"`
	Password   string `json:"password"`
	Phone      string `json:"phone,omitempty"`
	IDCard     string `json:"idCard,omitempty"`
	DeviceID   string `json:"deviceId"`
	Platform   string `json:"platform"`
	TenantID   string `json:"tenantId,omitempty"`
	BusinessID string `json:"businessId,omitempty"`
	Channel    string `json:"channel,omitempty"`
}

// Login 用户登录
func (c *APIClient) Login(ctx context.Context, req *LoginRequest) (*LoginResponse, error) {
	var resp LoginResponse
	err := c.do(ctx, "POST", "/app/auth/login", req, &resp)
	return &resp, err
}

// SendVerificationCode 发送邮箱验证码
func (c *APIClient) SendVerificationCode(ctx context.Context, req *SendCodeRequest) error {
	return c.do(ctx, "POST", "/app/auth/verification/send-code", req, nil)
}

// Register 用户注册
func (c *APIClient) Register(ctx context.Context, req *RegisterRequest) error {
	return c.do(ctx, "POST", "/app/auth/register", req, nil)
}
