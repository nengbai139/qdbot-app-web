package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"os"
	"time"

	"qdbot_app/client"
	"qdbot_app/internal/app"

	"github.com/spf13/viper"
)

func runSubcommand(args []string) {
	if len(args) == 0 {
		return
	}
	switch args[0] {
	case "send":
		runSendCmd(args[1:])
	case "ai":
		runAICmd(args[1:])
	case "sessions":
		runSessionsCmd(args[1:])
	case "groups":
		runGroupsCmd(args[1:])
	case "conversations":
		runConversationsCmd(args[1:])
	case "unread":
		runUnreadCmd(args[1:])
	case "help", "-h", "--help":
		printCLIHelp()
	default:
		fmt.Fprintf(os.Stderr, "unknown command: %s\n", args[0])
		printCLIHelp()
		os.Exit(2)
	}
}

func printCLIHelp() {
	fmt.Println(`QDBot CLI

  go run ./cmd/app/                              daemon (WS + auto reconnect)
  go run ./cmd/app/ send -to USER -m MSG         send single chat IM
  go run ./cmd/app/ send -group GROUP_ID -m MSG  send group chat IM
  go run ./cmd/app/ ai -m PROMPT                 ask AI agent
  go run ./cmd/app/ ai -conv ID -m PROMPT        continue AI conversation
  go run ./cmd/app/ sessions                     list IM sessions
  go run ./cmd/app/ groups                       list group chats
  go run ./cmd/app/ conversations                list AI conversations
  go run ./cmd/app/ unread                       show total unread count

Auth (first match wins):
  QDBOT_APP_TOKEN
  cached token in storage.path/auth_token.json
  QDBOT_EMAIL + QDBOT_PASSWORD
  interactive stdin (TTY)`)
}

func sendArgsValid(to, group, msg string) bool {
	if msg == "" {
		return false
	}
	return (to != "" && group == "") || (to == "" && group != "")
}

func newAuthedClient(platform string) (*client.APIClient, func()) {
	storage, err := app.NewStorage(viper.GetString("storage.path"))
	if err != nil {
		log.Fatalf("storage: %v", err)
	}
	api := client.NewAPIClient(&client.APIConfig{BaseURL: viper.GetString("qdbot_system.url")})
	token := resolveToken(api, storage, platform)
	return client.NewAPIClient(&client.APIConfig{
		BaseURL: viper.GetString("qdbot_system.url"),
		Token:   token,
	}), func() { _ = storage.Close() }
}

func runSendCmd(args []string) {
	fs := flag.NewFlagSet("send", flag.ExitOnError)
	to := fs.String("to", "", "peer user id (single chat)")
	group := fs.String("group", "", "group id (group chat)")
	msg := fs.String("m", "", "message content")
	fs.Parse(args)

	if !sendArgsValid(*to, *group, *msg) {
		fmt.Fprintln(os.Stderr, "usage: send (-to USER | -group GROUP_ID) -m MESSAGE")
		os.Exit(2)
	}

	api, cleanup := newAuthedClient(app.DetectPlatform().Name())
	defer cleanup()

	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()

	req := &client.SendIMRequest{Content: *msg, ContentType: "text"}
	if *group != "" {
		req.GroupID = *group
	} else {
		req.ToUserID = *to
	}

	resp, err := api.SendIM(ctx, req)
	if err != nil {
		log.Fatalf("send failed: %v", err)
	}
	id := resp.MsgID
	if id == "" {
		id = resp.MessageID
	}
	fmt.Printf("ok=%v msgId=%s\n", resp.OK, id)
}

func runAICmd(args []string) {
	fs := flag.NewFlagSet("ai", flag.ExitOnError)
	conv := fs.String("conv", "", "conversation id (optional)")
	msg := fs.String("m", "", "prompt")
	fs.Parse(args)

	if *msg == "" {
		fmt.Fprintln(os.Stderr, "usage: ai [-conv CONV_ID] -m PROMPT")
		os.Exit(2)
	}

	api, cleanup := newAuthedClient(app.DetectPlatform().Name())
	defer cleanup()

	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()

	resp, err := api.SendAI(ctx, &client.SendAIRequest{
		ConvID: *conv, Content: *msg, ContentType: "text",
	})
	if err != nil {
		log.Fatalf("ai failed: %v", err)
	}
	fmt.Printf("convId=%s messages=%d\n", resp.ConvID, len(resp.Messages))
	for _, m := range resp.Messages {
		fmt.Printf("[%s] %s\n", m.Role, m.Content)
	}
}

func runSessionsCmd(args []string) {
	fs := flag.NewFlagSet("sessions", flag.ExitOnError)
	fs.Parse(args)

	api, cleanup := newAuthedClient(app.DetectPlatform().Name())
	defer cleanup()

	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()

	resp, err := api.GetSessions(ctx)
	if err != nil {
		log.Fatalf("sessions failed: %v", err)
	}
	fmt.Printf("count=%d\n", resp.Count)
	for _, s := range resp.Sessions {
		fmt.Printf("%s peer=%s name=%q unread=%d last=%q\n",
			s.ID, s.PeerID, s.PeerName, s.Unread, s.LastMsg)
	}
}

func runUnreadCmd(args []string) {
	fs := flag.NewFlagSet("unread", flag.ExitOnError)
	fs.Parse(args)

	api, cleanup := newAuthedClient(app.DetectPlatform().Name())
	defer cleanup()

	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()

	resp, err := api.GetUnreadCount(ctx)
	if err != nil {
		log.Fatalf("unread failed: %v", err)
	}
	fmt.Printf("unread=%d\n", resp.UnreadCount)
}

func runGroupsCmd(args []string) {
	fs := flag.NewFlagSet("groups", flag.ExitOnError)
	fs.Parse(args)

	api, cleanup := newAuthedClient(app.DetectPlatform().Name())
	defer cleanup()

	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()

	resp, err := api.GetGroups(ctx)
	if err != nil {
		log.Fatalf("groups failed: %v", err)
	}
	fmt.Printf("count=%d\n", resp.Count)
	for _, g := range resp.Groups {
		name := g.GroupName
		if name == "" {
			name = g.Name
		}
		fmt.Printf("%s name=%q unread=%d last=%q\n", g.GroupID, name, g.UnreadCount, g.LastMsg)
	}
}

func runConversationsCmd(args []string) {
	fs := flag.NewFlagSet("conversations", flag.ExitOnError)
	fs.Parse(args)

	api, cleanup := newAuthedClient(app.DetectPlatform().Name())
	defer cleanup()

	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()

	resp, err := api.ListAIConversations(ctx)
	if err != nil {
		log.Fatalf("conversations failed: %v", err)
	}
	fmt.Printf("count=%d\n", resp.Count)
	for _, c := range resp.Conversations {
		fmt.Printf("%s title=%q model=%q\n", c.ConvID, c.Title, c.Model)
	}
}
