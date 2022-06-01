package env

import (
	"encoding/json"
	"io/ioutil"
	"log"
	"os"
)

var (
	configuration *Static
	ConfigFlag    string = "DOWNDETECTOR_CONFIG"
)

type Static struct {
	BotToken    string  `json:"bot_token"`
	BotGuild    string  `json:"bot_guild"`
	ChannelName string  `json:"channel_name"`
	Checks      []Check `json:"checks"`
}

type Check struct {
	Type       string      `json:"type"`
	Value      string      `json:"value"`
	Interval   string      `json:"interval"`
	Parameters *Parameters `json:"parameters"`
}

type Parameters struct {
	StatusCode int `json:"status_code"`
}

func Configuration() *Static {
	if configuration == nil {
		var path string
		if path = os.Getenv(ConfigFlag); path == "" {
			path = "./config.json"
		}

		file, err := ioutil.ReadFile(path)
		if err != nil {
			log.Printf("[ERROR] %s\n", err.Error())
			return nil
		}
		var s Static
		if err := json.Unmarshal(file, &s); err != nil {
			log.Printf("[ERROR] unmarshal file: %s", err.Error())
			return nil
		}
		configuration = &s

	}
	return configuration
}
