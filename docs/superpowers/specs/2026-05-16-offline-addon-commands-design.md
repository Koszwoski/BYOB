# Offline Addon Commands — Design Spec

**Date:** 2026-05-16  
**Status:** Approved

## Problem

`runAddonCommand` in `mineflayer-runtime.mjs` returns `"bot_not_running"` immediately when the bot is disconnected, before reaching any addon's `command()` function. Addons with file-based commands (e.g. sign-switcher's `add`/`remove`/`list`) cannot be used while the bot is offline.

## Goal

Allow addon commands to work even when the bot is not connected, for all addons that had been active during the last session.

## Design

### What changes

**`src/plugins/mineflayer-runtime.mjs` only — no addon changes.**

**1. New module-level map:**
```js
const offlineCommands = new Map(); // Map<botId, Map<addonName, commandFn>>
```

**2. In `loadAddonForRuntime` — cache the command function when an addon loads:**
```js
if (typeof instance.command === 'function') {
  if (!offlineCommands.has(runtime.botId))
    offlineCommands.set(runtime.botId, new Map());
  offlineCommands.get(runtime.botId).set(name, instance.command.bind(instance));
}
```

**3. In `disableBotAddon` — remove from cache when addon is explicitly disabled:**
```js
offlineCommands.get(botId)?.delete(name);
```

**4. In `runAddonCommand` — fall back to cache when bot is offline:**
```js
const runtime = runningBots.get(botId);
if (!runtime) {
  const commandFn = offlineCommands.get(botId)?.get(addonName);
  if (!commandFn) return { ok: false, error: "bot_not_running" };
  try {
    const result = await commandFn(sub, args);
    return { ok: true, result: String(result ?? "Done.") };
  } catch (err) {
    return { ok: false, error: err.message };
  }
}
// existing online logic unchanged below...
```

### Lifecycle

| Event | `offlineCommands` |
|---|---|
| Addon loads (`loadAddonForRuntime`) | Entry added/updated |
| Bot disconnects (`end` event) | Unchanged — commands stay cached |
| Bot stopped (`.disconnect`) | Unchanged — commands stay cached |
| Addon disabled (`.disable`) | Entry removed |
| Addon re-enabled and bot reconnects | Entry updated with new command fn |

### Limitation

If the bot has never connected (addon never initialized), there is no cached command function. The error remains `"bot_not_running"`. This is acceptable — `.enable` requires a running bot, so addons always have an active session before going offline.

### What does NOT change

- Addon interface (`init`, `command`, `cleanup`) — unchanged
- Online path in `runAddonCommand` — unchanged
- All other BYOB files — unchanged
- No addon repos need updating
