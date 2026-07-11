package main

import (
	"crypto/hmac"
	"crypto/sha1"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"
)

// ponytail: 独立 ICE/TURN 凭证服务；信令仍走 IM call_signal，媒体走 coturn
type config struct {
	Listen      string
	TurnSecret  string
	TurnHost    string
	StunURL     string
	AuthBaseURL string
	CredTTL     time.Duration
}

type iceServer struct {
	URLs       []string `json:"urls"`
	Username   string   `json:"username,omitempty"`
	Credential string   `json:"credential,omitempty"`
}

type iceResponse struct {
	IceServers []iceServer `json:"iceServers"`
	TTL        int         `json:"ttl"`
}

func loadConfig() config {
	ttlSec, _ := strconv.Atoi(env("WEBRTC_CRED_TTL_SEC", "86400"))
	return config{
		Listen:      env("WEBRTC_LISTEN", ":8099"),
		TurnSecret:  env("WEBRTC_TURN_SECRET", ""),
		TurnHost:    env("WEBRTC_TURN_HOST", "39.96.167.94"),
		StunURL:     env("WEBRTC_STUN_URL", "stun:stun.l.google.com:19302"),
		AuthBaseURL: strings.TrimRight(env("WEBRTC_AUTH_BASE", "https://www.aimatchem.com"), "/"),
		CredTTL:     time.Duration(ttlSec) * time.Second,
	}
}

func env(k, def string) string {
	if v := strings.TrimSpace(os.Getenv(k)); v != "" {
		return v
	}
	return def
}

func main() {
	cfg := loadConfig()
	if cfg.TurnSecret == "" {
		log.Fatal("WEBRTC_TURN_SECRET is required")
	}

	mux := http.NewServeMux()
	mux.HandleFunc("GET /health", func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("ok"))
	})
	mux.HandleFunc("GET /v1/ice-servers", func(w http.ResponseWriter, r *http.Request) {
		handleIceServers(w, r, cfg)
	})

	log.Printf("webrtc-relay listening on %s turn=%s", cfg.Listen, cfg.TurnHost)
	log.Fatal(http.ListenAndServe(cfg.Listen, mux))
}

func handleIceServers(w http.ResponseWriter, r *http.Request, cfg config) {
	token := bearerToken(r.Header.Get("Authorization"))
	if token == "" {
		http.Error(w, "missing token", http.StatusUnauthorized)
		return
	}
	if err := validateAppToken(cfg.AuthBaseURL, token); err != nil {
		http.Error(w, "invalid token", http.StatusUnauthorized)
		return
	}

	expiry := time.Now().Add(cfg.CredTTL).Unix()
	username := fmt.Sprintf("%d:qdbot", expiry)
	password := turnPassword(cfg.TurnSecret, username)

	host := cfg.TurnHost
	resp := iceResponse{
		TTL: int(cfg.CredTTL.Seconds()),
		IceServers: []iceServer{
			{URLs: []string{cfg.StunURL}},
			{URLs: []string{
				fmt.Sprintf("turn:%s:3478?transport=udp", host),
				fmt.Sprintf("turn:%s:3478?transport=tcp", host),
			}, Username: username, Credential: password},
		},
	}

	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Cache-Control", "private, max-age=300")
	_ = json.NewEncoder(w).Encode(resp)
}

func bearerToken(h string) string {
	h = strings.TrimSpace(h)
	if !strings.HasPrefix(strings.ToLower(h), "bearer ") {
		return ""
	}
	return strings.TrimSpace(h[7:])
}

func validateAppToken(baseURL, token string) error {
	req, err := http.NewRequest(http.MethodGet, baseURL+"/app/im/sessions", nil)
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Bearer "+token)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode == http.StatusOK {
		return nil
	}
	return fmt.Errorf("auth status %d", resp.StatusCode)
}

func turnPassword(secret, username string) string {
	mac := hmac.New(sha1.New, []byte(secret))
	_, _ = mac.Write([]byte(username))
	return base64.StdEncoding.EncodeToString(mac.Sum(nil))
}
