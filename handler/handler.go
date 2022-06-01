package handler

import (
	"log"
	"net"
	"net/http"
	"time"

	embed "github.com/Clinet/discordgo-embed"
	"github.com/bwmarrin/discordgo"
	env "github.com/infiniteloopcloud/discord-downdetector/env"
)

const (
	warning = 0xD10000
)

var channelName string

// Check is the endpoint alive
func Handle(body env.Check) (string, *discordgo.MessageEmbed, error) {
	var isAlive = true
	log.Printf("%s [INFO] Check happened for %s with %s type", time.Now().Format(time.RFC3339), body.Value, body.Type)
	switch body.Type {
	case "http":
		isAlive = checkHTTP(body)
	}
	if !isAlive {
		return unreachable(body)
	}
	return "", nil, nil
}

// Send an embed to the down detector channel
func unreachable(check env.Check) (string, *discordgo.MessageEmbed, error) {
	message := embed.NewEmbed().
		SetAuthor(check.Type + " detector check failed").
		SetTitle("[Host unreachable] " + check.Value).
		SetColor(warning)

	return env.Configuration().ChannelName, message.MessageEmbed, nil
}

// Return the status code of the request
func checkHTTP(body env.Check) bool {
	req, _ := http.NewRequest("GET", body.Value, nil)
	client := http.DefaultClient
	client.Timeout = 10 * time.Second
	netTransport := &http.Transport{
		DialContext: (&net.Dialer{
			Timeout: 10 * time.Second,
		}).DialContext,
		TLSHandshakeTimeout: 10 * time.Second,
	}
	client.Transport = netTransport

	resp, err := client.Do(req)
	if err != nil {
		log.Println("[ERROR]", err)
		return false
	}
	defer resp.Body.Close()

	var statusCode = http.StatusOK
	if body.Parameters != nil && body.Parameters.StatusCode != 0 {
		statusCode = body.Parameters.StatusCode
	}
	if resp.StatusCode != statusCode {
		return false
	}
	return true
}
