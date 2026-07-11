package client

import (
	"bytes"
	"context"
	"encoding/json"
	"log"
	"net/http"
	"time"
)

// PushConfig 推送配置
type PushConfig struct {
	FCMServerKey string // Firebase Cloud Messaging 服务器密钥
	FCMProjectID  string // Firebase 项目 ID
}

// PushClient 推送客户端
type PushClient struct {
	config *PushConfig
	httpClient *http.Client
}

// NewPushClient 创建推送客户端
func NewPushClient(config *PushConfig) (*PushClient, error) {
	if config == nil {
		config = &PushConfig{}
	}
	return &PushClient{
		config: config,
		httpClient: &http.Client{Timeout: 30 * time.Second},
	}, nil
}

// HandleNotification 处理推送通知
// App 端实现：接收 FCM/APNs 推送并展示
type NotificationHandler func(title, body, payload string)

// HandleToken 设备令牌刷新处理
type TokenHandler func(token, platform string)

// IsConfigured 检查是否已配置
func (p *PushClient) IsConfigured() bool {
	return p.config != nil && p.config.FCMProjectID != ""
}

// FCMMessage FCM 消息格式
type FCMMessage struct {
	To           string            `json:"to,omitempty"`
	Notification *FCMNotification  `json:"notification,omitempty"`
	Data         map[string]string `json:"data,omitempty"`
	Android      *FCMAndroid      `json:"android,omitempty"`
}

// FCMNotification FCM 通知内容
type FCMNotification struct {
	Title string `json:"title,omitempty"`
	Body  string `json:"body,omitempty"`
	Icon  string `json:"icon,omitempty"`
	Click string `json:"click_action,omitempty"`
}

// FCMAndroid Android 特定配置
type FCMAndroid struct {
	Priority string `json:"priority,omitempty"`
	Tag      string `json:"tag,omitempty"`
	Channel  string `json:"channel_id,omitempty"`
}

// SendFCM 发送 FCM 推送
func (p *PushClient) SendFCM(ctx context.Context, token, title, body string, data map[string]string) error {
	if !p.IsConfigured() {
		return nil // 未配置时静默忽略
	}

	msg := FCMMessage{
		To: token,
		Notification: &FCMNotification{
			Title: title,
			Body:  body,
		},
		Data: data,
		Android: &FCMAndroid{
			Priority: "high",
			Tag:      "qdbot_app",
		},
	}

	payload, err := json.Marshal(msg)
	if err != nil {
		return err
	}

	req, err := http.NewRequestWithContext(ctx, "POST",
		"https://fcm.googleapis.com/fcm/send",
		bytes.NewReader(payload))
	if err != nil {
		return err
	}

	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "key="+p.config.FCMServerKey)

	resp, err := p.httpClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return err
	}

	var result struct {
		Success int `json:"success"`
		Failure int `json:"failure"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return err
	}

	if result.Failure > 0 {
		log.Printf("[push] FCM send partial failure: success=%d failure=%d", result.Success, result.Failure)
	}

	return nil
}

// APNsPayload APNs 负载格式 (iOS)
type APNsPayload struct {
	APS APSConfig `json:"aps"`
	Msg  MsgContent `json:"msg,omitempty"`
}

// APSConfig APS 配置
type APSConfig struct {
	Alert            APSAlert `json:"alert"`
	Badge            int      `json:"badge,omitempty"`
	Sound            string   `json:"sound,omitempty"`
	ContentAvailable int      `json:"content-available,omitempty"`
	MutableContent   int      `json:"mutable-content,omitempty"`
}

// APSAlert Alert 内容
type APSAlert struct {
	Title string `json:"title,omitempty"`
	Subtitle string `json:"subtitle,omitempty"`
	Body  string `json:"body,omitempty"`
}

// MsgContent 消息内容
type MsgContent struct {
	Type       string `json:"contentType,omitempty"`
	Content   string `json:"content,omitempty"`
	From      string `json:"from,omitempty"`
	MsgID     string `json:"msgId,omitempty"`
	SessionID string `json:"sessionId,omitempty"`
}

// NotificationPayload 通知负载
type NotificationPayload struct {
	Title     string
	Body      string
	Badge     int
	Sound     string
	ContentType string
	Content    string
	FromID    string
	SessionID string
	MsgID     string
}

// NewAPNsPayload 创建 APNs 负载
func NewAPNsPayload(p *NotificationPayload) *APNsPayload {
	alert := APSAlert{Body: p.Body}
	if p.Title != "" {
		alert.Title = p.Title
	}

	apns := APSConfig{
		Alert: alert,
		Sound: "default",
	}
	if p.Badge > 0 {
		apns.Badge = p.Badge
	}
	if p.ContentType != "" {
		apns.ContentAvailable = 1
		apns.MutableContent = 1
	}

	msg := MsgContent{
		Type: p.ContentType,
	}
	if p.Content != "" {
		msg.Content = p.Content
		msg.From = p.FromID
		msg.SessionID = p.SessionID
		msg.MsgID = p.MsgID
	}

	return &APNsPayload{APS: apns, Msg: msg}
}

// Platform 平台类型
type Platform string

const (
	PlatformiOS     Platform = "ios"
	PlatformAndroid Platform = "android"
	PlatformPad     Platform = "pad"
	PlatformWeb     Platform = "web"
	PlatformUnknown Platform = "unknown"
)

// LocalNotification 本地通知 (App 端使用)
// 实现方式取决于 UI 框架 (Flutter: flutter_local_notifications, React Native: @notifee 等)
type LocalNotificationPayload struct {
	Title    string
	Body     string
	Data     map[string]interface{}
	Platform Platform
}

// DisplayNotification 显示通知 (由平台特定实现)
type DisplayNotification func(payload *LocalNotificationPayload) error

// SetDisplayNotification 设置平台通知显示函数
func SetDisplayNotification(fn DisplayNotification) {
	displayNotification = fn
}

var displayNotification DisplayNotification

// Display 显示通知
func Display(payload *LocalNotificationPayload) error {
	if displayNotification == nil {
		return nil
	}
	return displayNotification(payload)
}
