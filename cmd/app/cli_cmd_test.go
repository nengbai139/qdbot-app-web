package main

import "testing"

func TestSendArgsValid(t *testing.T) {
	tests := []struct {
		to, group, msg string
		ok             bool
	}{
		{"u1", "", "hi", true},
		{"", "g1", "hi", true},
		{"u1", "g1", "hi", false},
		{"", "", "hi", false},
		{"u1", "", "", false},
	}
	for _, tt := range tests {
		if got := sendArgsValid(tt.to, tt.group, tt.msg); got != tt.ok {
			t.Errorf("to=%q group=%q msg=%q: got %v want %v", tt.to, tt.group, tt.msg, got, tt.ok)
		}
	}
}
