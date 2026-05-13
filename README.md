# Build-Your-Own-Bot (BYOB)

A Discord-controlled Minecraft bot built around a tiny core and a
**lazy-loaded addon system**. The bot starts with nothing - just a
connection to Discord. You add the features you actually want
(anti-AFK, future: auto-eat, chat-relay, pathfinding, ...) by enabling
them per bot via Discord commands. Modules are only imported the first
time they are enabled, so a bot with no addons pays zero memory cost
for features it does not use.

## Memory footprint

Measured locally with one bot connected to a vanilla server:

| State | RSS |
|---|---|
| Idle (Discord connected, no MC) | ~85 MB |
| After `.auth` (prismarine-auth loaded) | ~95 MB |
| After `.connect` (mineflayer loaded, chunks streaming) | 130-160 MB |

The single biggest consumer left is `discord.js` (~40 MB); the
mineflayer chunk cache is controlled with `BOT_VIEW_DISTANCE=tiny`
(default).

## Install on a VPS (Debian/Ubuntu)

```bash
curl -fsSL https://raw.githubusercontent.com/Koszwoski/Build-Your-Own-Bot---BYOB/main/install.sh \
  | sudo bash
```

Then edit `/root/BYOB/.env` with your Discord token and channel ID,
or rerun the installer interactively. Service runs as
`systemctl status byob`.

## Discord commands

| Command | Alias | What |
|---|---|---|
| `.auth` | | Microsoft login (device code flow) |
| `.server <ip> [port]` | | Pick the Minecraft server |
| `.connect` | `.c` | Spawn the bot on that server |
| `.status` | `.s` | Embed with health, ping, coords, uptime |
| `.disconnect` | `.dc`, `.stop` | Leave MC server; will not auto-reconnect |
| `.allowlist` | | `on` / `off` / status — restrict who can use commands |
| `.bind` | | `.bind @user` or `.bind @user <botId>` (admins only) |
| `.unbind` | | `.unbind @user` (admins only) |
| `.addons` | `.a` | List addons + which are enabled / active |
| `.enable <name>` | `.e` | Turn an addon on (hot-loads if connected) |
| `.disable <name>` | `.d` | Turn an addon off (hot-unloads if connected) |
| `.help` | | Show all of this |

### Allow list (less spam in a busy channel)

1. Set `DISCORD_ADMIN_ROLE_ID` **or** `DISCORD_SUPERUSER_IDS` **or** use the **server owner** account.
2. `.allowlist on` — you are added to the list automatically.
3. `.bind @user` for each friend who should be allowed.

With allow list **on**, users not on the list get **no reply** (silent). `.help` still answers with a short note so people know to ask an admin.

With allow list **off**, behaviour is unchanged from before (role gate only).

## Writing an addon

Drop a file in `src/addons/`, then append its name to `AVAILABLE` in
`src/addons/index.mjs`:

```js
// src/addons/auto-eat.mjs
export const meta = {
  name: "auto-eat",
  description: "Eats food when hunger drops below threshold.",
  defaultConfig: { hungerThreshold: 14 },
};

export function init(bot, config, ctx) {
  function tick() {
    if (bot.food < config.hungerThreshold) {
      // ... eat logic ...
    }
  }
  const id = setInterval(tick, 5000);
  return { cleanup() { clearInterval(id); } };
}
```

The module is `import()`-ed the first time anyone runs `.enable auto-eat`.
A bot that never enables it pays zero cost.

## Configuration

Everything lives in `.env`:

| Variable | Default | Effect |
|---|---|---|
| `DISCORD_ENABLED` | `false` | Master switch for the Discord client |
| `DISCORD_TOKEN` | | Bot token |
| `DISCORD_CHANNEL_ID` | | The single channel BYOB listens in |
| `DISCORD_ADMIN_ROLE_ID` | | If set (and allow list off), only this role may issue commands |
| `DISCORD_SUPERUSER_IDS` | | Comma-separated user ids — always full access + can run `.allowlist` / `.bind` even without the admin role |
| `BOT_VIEW_DISTANCE` | `tiny` | Mineflayer view distance hint. Bigger = more RAM. |
| `BOT_CHAT_LIMIT` | `100` | Max chat message length kept in memory |

## State

`data/state.json` persists servers, bots, addon enable/disable, and
Discord links. `data/profiles/<discordUserId>/` holds Microsoft auth
caches so users don't re-login on restart. Both are gitignored.

## Companion: the panel

A web dashboard for BYOB lives in a separate repo:
[Bot-Panel---BYOB](https://github.com/Koszwoski/Bot-Panel---BYOB).
It is optional - BYOB is fully functional via Discord alone.
