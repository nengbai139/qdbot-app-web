package app

import (
	"testing"
)

func TestDetectPlatform(t *testing.T) {
	// 测试不同平台检测
	p := DetectPlatform()
	if p == "" {
		t.Error("DetectPlatform returned empty")
	}
}

func TestPlatform_Name(t *testing.T) {
	tests := []struct {
		platform Platform
		expected string
	}{
		{PlatformiOS, "ios"},
		{PlatformAndroid, "android"},
		{PlatformPad, "pad"},
		{PlatformWeb, "web"},
		{PlatformUnknown, "unknown"},
	}

	for _, tt := range tests {
		if tt.platform.Name() != tt.expected {
			t.Errorf("expected %s, got %s", tt.expected, tt.platform.Name())
		}
	}
}

func TestPlatform_IsMobile(t *testing.T) {
	if !PlatformiOS.IsMobile() {
		t.Error("iOS should be mobile")
	}
	if !PlatformAndroid.IsMobile() {
		t.Error("Android should be mobile")
	}
	if PlatformWeb.IsMobile() {
		t.Error("Web should not be mobile")
	}
	if PlatformPad.IsMobile() {
		t.Error("Pad should not be mobile (by default)")
	}
}

func TestPlatform_SupportsVoIP(t *testing.T) {
	if !PlatformiOS.SupportsVoIP() {
		t.Error("iOS should support VoIP")
	}
	if !PlatformAndroid.SupportsVoIP() {
		t.Error("Android should support VoIP")
	}
	if PlatformWeb.SupportsVoIP() {
		t.Error("Web should not support VoIP")
	}
}

func TestNormalizePlatform(t *testing.T) {
	tests := []struct {
		input    string
		expected Platform
	}{
		{"ios", PlatformiOS},
		{"IOS", PlatformiOS},
		{"iPhone", PlatformiOS},
		{"iPad", PlatformiOS},
		{"android", PlatformAndroid},
		{"Android", PlatformAndroid},
		{"arm", PlatformAndroid},
		{"arm64", PlatformAndroid},
		{"pad", PlatformPad},
		{"tablet", PlatformPad},
		{"web", PlatformWeb},
		{"browser", PlatformWeb},
		{"desktop", PlatformWeb},
		{"unknown", PlatformUnknown},
		{"", PlatformUnknown},
	}

	for _, tt := range tests {
		result := NormalizePlatform(tt.input)
		if result != tt.expected {
			t.Errorf("NormalizePlatform(%s): expected %s, got %s", tt.input, tt.expected, result)
		}
	}
}

func TestPlatform_Constants(t *testing.T) {
	if PlatformiOS != "ios" {
		t.Errorf("expected PlatformiOS=ios, got %s", PlatformiOS)
	}
	if PlatformAndroid != "android" {
		t.Errorf("expected PlatformAndroid=android, got %s", PlatformAndroid)
	}
	if PlatformPad != "pad" {
		t.Errorf("expected PlatformPad=pad, got %s", PlatformPad)
	}
	if PlatformWeb != "web" {
		t.Errorf("expected PlatformWeb=web, got %s", PlatformWeb)
	}
	if PlatformUnknown != "unknown" {
		t.Errorf("expected PlatformUnknown=unknown, got %s", PlatformUnknown)
	}
}

func TestDeviceInfo_Structure(t *testing.T) {
	info := DeviceInfo{
		Platform:    PlatformiOS,
		OSVersion:  "17.0",
		AppVersion: "1.0.0",
		DeviceModel: "iPhone 15 Pro",
		DeviceID:   "device_123",
	}

	if info.Platform != PlatformiOS {
		t.Errorf("expected Platform=iOS, got %s", info.Platform)
	}
	if info.OSVersion != "17.0" {
		t.Errorf("expected OSVersion=17.0, got %s", info.OSVersion)
	}
	if info.AppVersion != "1.0.0" {
		t.Errorf("expected AppVersion=1.0.0, got %s", info.AppVersion)
	}
}
