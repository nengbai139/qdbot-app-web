package app

import (
	"os"
	"runtime"
	"strings"
)

// Platform 平台类型
type Platform string

const (
	PlatformiOS     Platform = "ios"
	PlatformAndroid Platform = "android"
	PlatformPad     Platform = "pad"
	PlatformWeb     Platform = "web"
	PlatformUnknown Platform = "unknown"
)

// DetectPlatform 检测当前运行平台
func DetectPlatform() Platform {
	goos := runtime.GOOS

	switch goos {
	case "darwin":
		return PlatformiOS // 实际需要结合 UI 框架判断 iPad/Mac
	case "ios":
		return PlatformiOS
	case "android":
		return PlatformAndroid
	case "linux":
		if isTermux() {
			return PlatformAndroid
		}
		return PlatformWeb
	case "windows", "js", "wasip1":
		return PlatformWeb
	}

	return PlatformUnknown
}

func isTermux() bool {
	_, exists := os.LookupEnv("TERMUX")
	return exists
}

// DeviceInfo 设备信息
type DeviceInfo struct {
	Platform    Platform
	OSVersion   string
	AppVersion  string
	DeviceModel string
	DeviceID    string
}

// Name 返回平台名称
func (p Platform) Name() string {
	return string(p)
}

// IsMobile 是否移动平台
func (p Platform) IsMobile() bool {
	return p == PlatformiOS || p == PlatformAndroid
}

// SupportsVoIP 是否支持 VoIP 推送
func (p Platform) SupportsVoIP() bool {
	return p == PlatformiOS || p == PlatformAndroid
}

// NormalizePlatform 规范化平台字符串
func NormalizePlatform(s string) Platform {
	s = strings.ToLower(strings.TrimSpace(s))
	switch s {
	case "ios", "iphone", "ipad":
		return PlatformiOS
	case "android", "arm", "arm64":
		return PlatformAndroid
	case "pad", "tablet":
		return PlatformPad
	case "web", "browser", "desktop":
		return PlatformWeb
	default:
		return PlatformUnknown
	}
}
