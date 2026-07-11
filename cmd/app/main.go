package main

import (
	"flag"
	"log"
	"os"
	"os/signal"
	"sync/atomic"
	"syscall"
	"time"

	"qdbot_app/client"
	"qdbot_app/internal/app"
	"qdbot_app/internal/chat"

	"github.com/spf13/viper"
)

var (
	version = "1.0.0"
	commit  = "dev"
)

func main() {
	log.Printf("QDBot App v%s (commit: %s)", version, commit)

	args := os.Args[1:]
	if len(args) > 0 && isCLISubcommand(args[0]) {
		if err := initConfig("configs/config.yaml"); err != nil {
			log.Fatalf("Failed to init config: %v", err)
		}
		runSubcommand(args)
		return
	}

	configPath := flag.String("config", "configs/config.yaml", "config file path")
	flutterMode := flag.Bool("flutter", false, "Run in Flutter bridge mode")
	flag.Parse()

	if err := initConfig(*configPath); err != nil {
		log.Fatalf("Failed to init config: %v", err)
	}

	if *flutterMode {
		runFlutterBridge()
		return
	}

	runCLI()
}

func isCLISubcommand(name string) bool {
	switch name {
	case "send", "ai", "sessions", "groups", "conversations", "unread", "help":
		return true
	default:
		return false
	}
}

func runCLI() {
	// 初始化存储
	storage, err := app.NewStorage(viper.GetString("storage.path"))
	if err != nil {
		log.Fatalf("Failed to init storage: %v", err)
	}
	defer storage.Close()

	// 初始化平台检测
	platform := app.DetectPlatform()

	apiClient := client.NewAPIClient(&client.APIConfig{
		BaseURL: viper.GetString("qdbot_system.url"),
	})
	token := resolveToken(apiClient, storage, platform.Name())
	apiClient = client.NewAPIClient(&client.APIConfig{
		BaseURL: viper.GetString("qdbot_system.url"),
		Token:   token,
	})

	// 初始化推送客户端
	pushClient, err := client.NewPushClient(&client.PushConfig{
		FCMServerKey: viper.GetString("push.fcm.server_key"),
		FCMProjectID:  viper.GetString("push.fcm.project_id"),
	})
	if err != nil {
		log.Printf("Push client init failed: %v (continuing without push)", err)
	}
	_ = pushClient // 暂未使用

	// 初始化会话管理器
	sessionMgr := app.NewSessionManager(storage)

	// 初始化聊天服务
	chatService := chat.NewService(&chat.Config{
		QDBotSystemURL: viper.GetString("qdbot_system.url"),
		APIVersion:     viper.GetString("qdbot_system.api_version"),
	}, storage)
	chatService.SetAPIClient(apiClient)

	// 初始化 WebSocket 客户端
	wsURL := viper.GetString("qdbot_system.ws_url")
	if wsURL == "" {
		wsURL = "ws://localhost:8080/ws"
	}
	var wsClient *client.WSClient
	var reconnecting int32 // 原子标记：防止重复重连 goroutine

	wsClient = client.NewWSClient(&client.WSConfig{
		URL:      wsURL,
		Token:    token,
		Platform: platform.Name(),
		OnMessage:  chatService.HandleMessage,
		OnConnect:  chatService.OnConnect,
		OnDisconnect: func(err error) {
			chatService.OnDisconnect(err)
			// 原子 CAS 确保只有一个重连 goroutine
			if !atomic.CompareAndSwapInt32(&reconnecting, 0, 1) {
				return
			}
			go func() {
				defer atomic.StoreInt32(&reconnecting, 0)
				rc := client.NewReconnectContext(wsClient)
				if rerr := rc.Do(5 * time.Minute); rerr != nil {
					log.Printf("[ws] reconnect failed: %v", rerr)
				}
			}()
		},
	})

	// 启动
	sessionMgr.Start()
	chatService.Start()
	wsClient.Connect()

	// 等待信号
	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)
	<-sigCh

	log.Println("Shutting down...")

	wsClient.Close()
	chatService.Stop()
	sessionMgr.Stop()

	log.Println("Shutdown complete")
}

func runFlutterBridge() {
	apiClient := client.NewAPIClient(&client.APIConfig{
		BaseURL: viper.GetString("qdbot_system.url"),
	})
	storagePath := viper.GetString("storage.path")
	storage, _ := app.NewStorage(storagePath)
	token := resolveToken(apiClient, storage, "flutter")

	// 创建 Flutter 桥接器
	bridge := NewFlutterBridge(&BridgeConfig{
		WSURL:       viper.GetString("qdbot_system.ws_url"),
		APIBaseURL:  viper.GetString("qdbot_system.url"),
		Token:       token,
		Platform:    "flutter",
		FCMKey:      viper.GetString("push.fcm.server_key"),
		FCMProject:  viper.GetString("push.fcm.project_id"),
		StoragePath: viper.GetString("storage.path"),
	})

	// 初始化
	if err := bridge.Init(); err != nil {
		log.Fatalf("Failed to init Flutter bridge: %v", err)
	}

	// 启动
	bridge.Start()

	log.Println("[FlutterBridge] Running...")

	// 等待信号
	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)
	<-sigCh

	log.Println("Shutting down Flutter bridge...")
	bridge.Stop()
	log.Println("Shutdown complete")
}

func initConfig(configPath string) error {
	viper.SetConfigFile(configPath)
	viper.SetConfigType("yaml")

	// 默认值
	viper.SetDefault("storage.path", "./data")
	viper.SetDefault("qdbot_system.url", "http://localhost:8080")
	viper.SetDefault("qdbot_system.api_version", "v1")
	viper.SetDefault("qdbot_system.ws_url", "ws://localhost:8080/ws")

	// 从环境变量覆盖
	viper.AutomaticEnv()

	return viper.ReadInConfig()
}
