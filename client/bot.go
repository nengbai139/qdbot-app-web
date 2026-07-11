package client

import "context"

// BotConfig AI 数字分身配置
type BotConfig struct {
	Enabled        bool   `json:"enabled"`
	Persona        string `json:"persona,omitempty"`
	DefaultSkillID string `json:"defaultSkillId,omitempty"`
}

// GetBotConfig 获取数字分身配置
func (c *APIClient) GetBotConfig(ctx context.Context) (*BotConfig, error) {
	var resp BotConfig
	err := c.do(ctx, "GET", "/app/im/bot/config", nil, &resp)
	return &resp, err
}

// UpdateBotConfig 更新数字分身配置
func (c *APIClient) UpdateBotConfig(ctx context.Context, cfg *BotConfig) error {
	return c.do(ctx, "PUT", "/app/im/bot/config", cfg, nil)
}
