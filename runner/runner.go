package runner

import (
	"log"
	"sync"
	"time"

	"github.com/infiniteloopcloud/discord-downdetector/env"
	handler "github.com/infiniteloopcloud/discord-downdetector/handler"
	utils "github.com/infiniteloopcloud/discord-downdetector/utils"
)

func check(body env.Check) {
	channel, message, err := handler.Handle(body)
	if err != nil {
		log.Printf("[ERROR] %s", err.Error())
		return
	}
	channelID := utils.GetChannelID(channel)
	if channelID == "" {
		channelID = utils.GetChannelID("unknown")
	}
	if channelID != "" && message != nil {
		_, err = utils.GetSession().ChannelMessageSendEmbed(channelID, message)
		if err != nil {
			log.Printf("[ERROR] %s", err.Error())
		}
	}
}

func Run() {
	log.Printf("[RUNNING] Downdetector")

	wg := &sync.WaitGroup{}

	for i := range env.Configuration().Checks {
		wg.Add(1)
		go func(innerWg *sync.WaitGroup, i int) {
			for {
				check(env.Configuration().Checks[i])

				interval, unit := utils.GetTime(env.Configuration().Checks[i].Interval)
				switch unit {
				case "h":
					time.Sleep(time.Duration(interval) * time.Hour)
				case "m":
					time.Sleep(time.Duration(interval) * time.Minute)
				case "s":
					time.Sleep(time.Duration(interval) * time.Second)
				}
			}
			innerWg.Done()
		}(wg, i)

	}

	wg.Wait()
}
