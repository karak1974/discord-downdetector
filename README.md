# discord-downdetector
Detects service failures and sends notifications if something is down.

### Config example

```json
{
  "bot_token": "BOT_TOKEN",
  "bot_guild": "GUILD_ID",
  "channel_name": "downdetector",
  "checks": [
    {
      "type": "http",
      "value": "https://test.com/hc",
      "interval": "120m"
    }
  ]
}
```
