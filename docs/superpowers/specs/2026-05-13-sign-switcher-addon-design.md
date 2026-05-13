# Sign-Switcher Addon Design

## Overview

A mineflayer addon for BYOB that wanders the world, finds signs, breaks them, and places them back with random text from a user-defined preset list. Controlled entirely via Discord using a generic `.addon <name> <subcommand>` command added to BYOB core.

---

## Part 1: BYOB Core Changes

### discord-control.mjs

New command: `.addon <addon-name> <subcommand> [args...]`

- Only available when a bot is running and the named addon is active
- Calls `instance.command(subcommand, args)` on the active addon instance
- Returns the string result to Discord
- Access control follows existing rules (allowlist, role gate)

Example:
```
.addon sign-switcher add MyPreset "Hello" "World" "" ""
.addon sign-switcher remove MyPreset
.addon sign-switcher list
```

### mineflayer-runtime.mjs

Addon instances may optionally return a `command(sub, args)` method alongside `cleanup()`. No changes to how addons are loaded — the method is simply called if it exists when a `.addon` Discord command is received.

Extended addon return interface:
```js
return {
  cleanup() {},
  async command(subcommand, args) {
    // Returns a string shown in Discord
  }
}
```

---

## Part 2: Sign-Switcher-Addon (new repo)

### Repo name: `Sign-Switcher-Addon`

### Files
- `sign-switcher.mjs` — the addon
- `README.md` — installation instructions

### Installation (user steps)
1. Copy `sign-switcher.mjs` into BYOB's `src/addons/`
2. Add `"sign-switcher"` to `AVAILABLE` in `src/addons/index.mjs`
3. Run `pnpm add mineflayer-pathfinder` in the BYOB directory
4. Enable with `.enable sign-switcher` in Discord

### Preset Storage

Presets are stored in `data/sign-switcher-presets.json` in BYOB's working directory. The file is created automatically on first use. Format:

```json
{
  "presets": {
    "MyPreset": ["Hello", "World", "", ""],
    "AnotherPreset": ["Line 1", "Line 2", "Line 3", "Line 4"]
  }
}
```

### Discord Commands (via `.addon sign-switcher`)

| Command | Description |
|---|---|
| `add <name> <l1> <l2> <l3> <l4>` | Add or overwrite a preset |
| `remove <name>` | Remove a preset |
| `list` | List all preset names |

### State Machine

```
WANDERING → BREAKING → COLLECTING → PLACING → WRITING → WANDERING
```

- **WANDERING**: pathfinder walks to random positions within ±100 blocks. Every 20 ticks, scans for signs within 64 blocks using `bot.findBlock({ maxDistance: 64 })`.
- **BREAKING**: `bot.dig(block)` on the found sign. Timeout: 20s.
- **COLLECTING**: waits for the sign item to appear in inventory (via `bot.on('playerCollect')`). Timeout: 5s.
- **PLACING**: navigates adjacent to the original position and places the sign via `bot.placeBlock()`. Timeout: 20s.
- **WRITING**: sends sign text via `bot.updateSign()` after a short delay (250ms) to allow server-side block entity to register. Then returns to WANDERING.

### Loop Prevention

Before targeting a sign, the addon reads its current text. If it already matches any stored preset, the sign is skipped.

### Sign Finding

Uses `bot.findBlock()` matching any block name containing `"sign"`. Signs with text matching any preset are skipped. Signs with no adjacent solid block for placement are skipped.

### Dependencies

- `mineflayer-pathfinder` — navigation and block approach

### Default Config

```js
{
  scanIntervalTicks: 20,
  wanderRange: 100,
  writeDelayMs: 250,
}
```

---

## Out of Scope

- Hanging sign support (ceiling geometry unsupported by pathfinder placement)
- Per-bot preset isolation (presets are shared across all bots using this addon)
- Sign reading from signs the bot did not place
