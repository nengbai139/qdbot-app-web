package main

import (
	"bufio"
	"context"
	"fmt"
	"log"
	"os"
	"strings"

	"qdbot_app/client"
	"qdbot_app/internal/app"
)

// resolveToken: env token → storage → env login → interactive stdin login
func resolveToken(api *client.APIClient, storage *app.FileStorage, platform string) string {
	if t := os.Getenv("QDBOT_APP_TOKEN"); t != "" {
		return t
	}
	if storage != nil {
		if t, err := storage.LoadAuthToken(); err == nil && t != "" {
			return t
		}
	}
	email, pass := os.Getenv("QDBOT_EMAIL"), os.Getenv("QDBOT_PASSWORD")
	if email != "" && pass != "" {
		return loginAndSave(api, storage, email, pass, platform, os.Getenv("QDBOT_DEVICE_ID"))
	}
	if stdinIsTerminal() {
		return interactiveLogin(api, storage, platform)
	}
	log.Fatal("no auth: set QDBOT_APP_TOKEN, QDBOT_EMAIL+QDBOT_PASSWORD, or run in a terminal")
	return ""
}

func loginAndSave(api *client.APIClient, storage *app.FileStorage, email, pass, platform, deviceID string) string {
	if deviceID == "" {
		deviceID = "cli_device"
	}
	resp, err := api.Login(context.Background(), &client.LoginRequest{
		Email: email, Password: pass, DeviceID: deviceID, Platform: platform,
	})
	if err != nil {
		log.Fatalf("login failed: %v", err)
	}
	if resp.Token == "" {
		log.Fatalf("login failed: empty token (%s)", resp.Error)
	}
	if storage != nil {
		_ = storage.SaveAuthToken(resp.Token)
	}
	log.Printf("[auth] logged in as %s", resp.UserID)
	return resp.Token
}

func interactiveLogin(api *client.APIClient, storage *app.FileStorage, platform string) string {
	fmt.Println("QDBot CLI login")
	r := bufio.NewReader(os.Stdin)
	fmt.Print("Email: ")
	email, _ := r.ReadString('\n')
	fmt.Print("Password: ")
	pass, _ := r.ReadString('\n')
	return loginAndSave(api, storage, strings.TrimSpace(email), strings.TrimSpace(pass), platform, "")
}

func stdinIsTerminal() bool {
	fi, err := os.Stdin.Stat()
	if err != nil {
		return false
	}
	return fi.Mode()&os.ModeCharDevice != 0
}
