# BYOB: Multi-bot command router

## Overview

Single Discord token controls N numbered Mineflayer bots. User targets bots with
`.cmd <targets> <command>` syntax. All bots run in one Node.js process.

## Target syntax

| Input       | Resolves to       |
|-------------|-------------------|
| `1-3`       | [1, 2, 3]         |
| `1,3,5`     | [1, 3, 5]         |
| `1-3,5`     | [1, 2, 3, 5]      |
| `all`       | all configured bots |

## Data flow

1. User writes `.cmd 1-3 .connect 2b2t.org` in Discord
2. Discord client receives message
3. Target parser extracts [1, 2, 3], rest = `.connect 2b2t.org`
4. Existing command handler called for each bot with bot context
5. Responses aggregated and posted as one Discord message:
   ```
   [1] ✅ Connecting...
   [2] ✅ Connecting...
   [3] ⚠️ Bot 3 ikke fundet
   ```

## Configuration

One `.env` for all bots:

```
BOT_COUNT=3
DISCORD_TOKEN=xxx
DISCORD_SUPERUSER_IDS=123456789
```

Bots are auto-created as bot1, bot2, bot3 in state.json on first start.

## Files changed

| File | Change |
|------|--------|
| `src/lib/target-parser.mjs` | New — parses target strings into bot ID arrays |
| `src/plugins/discord-control.mjs` | Add `.cmd` handler, route to existing handlers |
| `src/main.mjs` | Boot N bots from BOT_COUNT instead of one |

## Out of scope

- Per-bot Discord channels
- Webhook responses per bot
- Web dashboard
