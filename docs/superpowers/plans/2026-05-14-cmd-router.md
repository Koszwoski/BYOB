# Multi-bot .cmd Router Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `.cmd <targets> <command>` to BYOB so one Discord bot controls N numbered Mineflayer bots.

**Architecture:** A target parser turns `1-3`, `1,5`, `all` into bot numbers. Numbered bots are auto-created on startup from `BOT_COUNT`. The `.cmd` handler in discord-control routes each sub-command to existing runtime functions by bot ID directly, aggregating responses into one Discord reply.

**Tech Stack:** Node.js ESM, discord.js, existing mineflayer-runtime.mjs, data.mjs

---

### Task 1: Target parser

**Files:**
- Create: `src/lib/target-parser.mjs`
- Create: `src/lib/target-parser.test.mjs`

- [ ] **Step 1: Create test file**

```js
// src/lib/target-parser.test.mjs
import assert from "node:assert/strict";
import { test } from "node:test";
import { parseTargets } from "./target-parser.mjs";

test("range: 1-3 returns [1,2,3]", () => {
  assert.deepEqual(parseTargets("1-3", 5), [1, 2, 3]);
});

test("list: 1,3,5 returns [1,3,5]", () => {
  assert.deepEqual(parseTargets("1,3,5", 5), [1, 3, 5]);
});

test("mixed: 1-3,5 returns [1,2,3,5]", () => {
  assert.deepEqual(parseTargets("1-3,5", 5), [1, 2, 3, 5]);
});

test("all: returns all bots 1..maxBots", () => {
  assert.deepEqual(parseTargets("all", 3), [1, 2, 3]);
});

test("clamps to maxBots: 1-10 with maxBots=3 returns [1,2,3]", () => {
  assert.deepEqual(parseTargets("1-10", 3), [1, 2, 3]);
});

test("deduplicates: 1-3,2 returns [1,2,3]", () => {
  assert.deepEqual(parseTargets("1-3,2", 3), [1, 2, 3]);
});

test("invalid input returns []", () => {
  assert.deepEqual(parseTargets("abc", 3), []);
});
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd ~/build-your-own-bot && node --test src/lib/target-parser.test.mjs
```

Expected: `Error: Cannot find module './target-parser.mjs'`

- [ ] **Step 3: Implement target parser**

```js
// src/lib/target-parser.mjs

/**
 * Parse a target string into a sorted, deduplicated array of bot numbers.
 * @param {string} input - e.g. "1-3", "1,3,5", "1-3,5", "all"
 * @param {number} maxBots - upper bound (inclusive)
 * @returns {number[]}
 */
export function parseTargets(input, maxBots) {
  if (!input || !maxBots) return [];
  if (input.trim().toLowerCase() === "all") {
    return Array.from({ length: maxBots }, (_, i) => i + 1);
  }

  const result = new Set();
  const parts = input.split(",");

  for (const part of parts) {
    const trimmed = part.trim();
    const range = trimmed.match(/^(\d+)-(\d+)$/);
    if (range) {
      const from = Math.max(1, parseInt(range[1], 10));
      const to = Math.min(maxBots, parseInt(range[2], 10));
      for (let i = from; i <= to; i++) result.add(i);
      continue;
    }
    const single = trimmed.match(/^(\d+)$/);
    if (single) {
      const n = parseInt(single[1], 10);
      if (n >= 1 && n <= maxBots) result.add(n);
    }
  }

  return [...result].sort((a, b) => a - b);
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
node --test src/lib/target-parser.test.mjs
```

Expected: all 7 tests pass

- [ ] **Step 5: Commit**

```bash
git add src/lib/target-parser.mjs src/lib/target-parser.test.mjs
git commit -m "Target parser: parseTargets for .cmd routing"
```

---

### Task 2: Numbered bots in data.mjs

**Files:**
- Modify: `src/data.mjs`

- [ ] **Step 1: Read current data.mjs exports**

```bash
grep -n "^export function\|^export const\|^export let" src/data.mjs
```

Note the existing exports — we will add two new ones without touching anything existing.

- [ ] **Step 2: Add getBotByNumber and initNumberedBots**

Append to the bottom of `src/data.mjs`:

```js
/**
 * Get a bot by its 1-based number (the `number` field on the bot object).
 * @param {number} n
 * @returns {object|null}
 */
export function getBotByNumber(n) {
  return bots.find((b) => b.number === n) ?? null;
}

/**
 * Ensure bots numbered 1..count exist in state. Creates missing ones.
 * Existing bots are never modified.
 * @param {number} count
 */
export function initNumberedBots(count) {
  for (let n = 1; n <= count; n++) {
    const exists = bots.find((b) => b.number === n);
    if (!exists) {
      addBot({ id: `bot${n}`, name: `bot${n}`, username: `bot${n}`, number: n });
    }
  }
  flushStateSync();
}
```

- [ ] **Step 3: Verify the file is valid ESM**

```bash
node --input-type=module <<'EOF'
import { getBotByNumber, initNumberedBots } from "./src/data.mjs";
console.log("ok", typeof getBotByNumber, typeof initNumberedBots);
EOF
```

Expected: `ok function function`

- [ ] **Step 4: Commit**

```bash
git add src/data.mjs
git commit -m "data: getBotByNumber + initNumberedBots"
```

---

### Task 3: Auto-init numbered bots on startup

**Files:**
- Modify: `src/main.mjs`

- [ ] **Step 1: Add import**

In `src/main.mjs`, add `initNumberedBots` to the existing import from `./data.mjs`:

```js
// find this line:
import {
  addBot,
  // ... existing imports
} from "./data.mjs";

// add initNumberedBots to the list
```

- [ ] **Step 2: Add startup call**

After the existing `resumePersistedBots` call in `src/main.mjs`:

```js
const botCount = parseInt(process.env.BOT_COUNT ?? "0", 10);
if (botCount > 0) {
  initNumberedBots(botCount);
  console.log(`[init] ${botCount} numbered bot(s) ready`);
}
```

- [ ] **Step 3: Update .env.example**

Add to `.env.example` (or create it if missing):

```
# Number of numbered bots (bot1, bot2, ... botN)
BOT_COUNT=3
DISCORD_TOKEN=
DISCORD_CHANNEL_ID=
DISCORD_SUPERUSER_IDS=
DISCORD_ENABLED=true
```

- [ ] **Step 4: Verify startup doesn't crash**

```bash
BOT_COUNT=3 DISCORD_ENABLED=false node src/main.mjs &
sleep 2 && kill %1
```

Expected output includes: `[init] 3 numbered bot(s) ready`

- [ ] **Step 5: Commit**

```bash
git add src/main.mjs .env.example
git commit -m "main: auto-init BOT_COUNT numbered bots on startup"
```

---

### Task 4: .cmd handler in discord-control

**Files:**
- Modify: `src/plugins/discord-control.mjs`

This task adds the `.cmd` command. It routes sub-commands to the existing runtime functions by bot ID directly — no discordUserId lookup needed.

- [ ] **Step 1: Add imports to discord-control.mjs**

Add to the existing imports at the top of `src/plugins/discord-control.mjs`:

```js
import { parseTargets } from "../lib/target-parser.mjs";
import { getBotByNumber, getServer } from "../data.mjs";
```

Note: `getServer` is already imported from `data.mjs` — only add what's missing.

- [ ] **Step 2: Add the runCmd helper function**

Add this function before `export async function startDiscordControl`:

```js
/**
 * Execute a single BYOB sub-command against a specific bot by ID.
 * Returns a string result for the aggregated reply.
 */
async function runCmdForBot(botNum, bot, subCommand, subArgs, handlers) {
  const {
    runBotActionById,
    getStatusById,
    enableAddonById,
    disableAddonById,
    runAddonCommandById,
  } = handlers;

  const prefix = `[${botNum}]`;

  if (!bot) return `${prefix} ⚠️ Bot ${botNum} ikke fundet`;

  try {
    if (subCommand === "connect" || subCommand === "c") {
      const host = subArgs[0];
      if (host) {
        const port = subArgs[1] ? Number(subArgs[1]) : 25565;
        await handlers.setServerById(bot.id, host, port);
      }
      const result = await runBotActionById(bot.id, "start");
      if (result.error) return `${prefix} ❌ ${result.error}`;
      return `${prefix} ✅ Connecting...`;
    }

    if (subCommand === "disconnect" || subCommand === "dc") {
      const result = await runBotActionById(bot.id, "stop");
      if (result.error) return `${prefix} ❌ ${result.error}`;
      return `${prefix} ✅ Disconnected`;
    }

    if (subCommand === "status" || subCommand === "s") {
      const result = getStatusById(bot.id);
      const s = result.bot?.status ?? "unknown";
      const emoji = s === "online" ? "🟢" : s === "connecting" ? "🟡" : "🔴";
      return `${prefix} ${emoji} ${s}`;
    }

    if (subCommand === "enable" || subCommand === "e") {
      const [name] = subArgs;
      if (!name) return `${prefix} ⚠️ Usage: .enable <addon>`;
      const result = await enableAddonById(bot.id, name);
      if (!result.ok) return `${prefix} ❌ ${result.error}`;
      return `${prefix} ✅ ${name} enabled`;
    }

    if (subCommand === "disable" || subCommand === "d") {
      const [name] = subArgs;
      if (!name) return `${prefix} ⚠️ Usage: .disable <addon>`;
      const result = disableAddonById(bot.id, name);
      if (!result.ok) return `${prefix} ❌ ${result.error}`;
      return `${prefix} ✅ ${name} disabled`;
    }

    if (subCommand === "addon") {
      const [addonName, sub, ...addonArgs] = subArgs;
      if (!addonName || !sub) return `${prefix} ⚠️ Usage: .addon <name> <sub> [args]`;
      const result = await runAddonCommandById(bot.id, addonName, sub, addonArgs);
      if (!result.ok) return `${prefix} ❌ ${result.error}`;
      return `${prefix} ✅ ${result.result}`;
    }

    return `${prefix} ⚠️ Unknown sub-command: ${subCommand}`;
  } catch (err) {
    return `${prefix} ❌ ${err.message}`;
  }
}
```

- [ ] **Step 3: Add handler functions to startDiscordControl parameters**

`startDiscordControl` already receives action functions as parameters. Add these four new ones to the parameter destructure at the top of `startDiscordControl`:

```js
export async function startDiscordControl({
  // ... existing params ...
  runBotActionById,    // (botId, action) => result
  getStatusById,       // (botId) => { bot, server, runtime }
  setServerById,       // (botId, host, port) => void
  enableAddonById,     // (botId, name) => result
  disableAddonById,    // (botId, name) => result
  runAddonCommandById, // (botId, addonName, sub, args) => result
  getBotCount,         // () => number
  logger = console,
}) {
```

- [ ] **Step 4: Add .cmd command in the messageCreate handler**

In the `messageCreate` handler, add this block after the permission checks and before the `if (command === "auth")` block:

```js
if (command === "cmd") {
  if (!hasManagementPermission(message, adminRoleId)) {
    await message.reply("Only admins can use `.cmd`.");
    return;
  }

  // args[0] = target string, rest = sub-command
  const [targetStr, subRaw, ...subArgs] = args;
  if (!targetStr || !subRaw) {
    await message.reply("Usage: `.cmd <targets> .<command> [args]`\nExample: `.cmd 1-3 .connect 2b2t.org`");
    return;
  }

  // Strip leading dot from sub-command if present
  const subCommand = subRaw.startsWith(".") ? subRaw.slice(1).toLowerCase() : subRaw.toLowerCase();

  const maxBots = getBotCount();
  const targets = parseTargets(targetStr, maxBots);

  if (targets.length === 0) {
    await message.reply(`No valid targets in \`${targetStr}\`. Use e.g. \`1-3\`, \`1,5\`, \`all\`.`);
    return;
  }

  const handlers = {
    runBotActionById,
    getStatusById,
    setServerById,
    enableAddonById,
    disableAddonById,
    runAddonCommandById,
  };

  const lines = await Promise.all(
    targets.map((n) => {
      const bot = getBotByNumber(n);
      return runCmdForBot(n, bot, subCommand, subArgs, handlers);
    })
  );

  await message.reply(lines.join("\n"));
  return;
}
```

- [ ] **Step 5: Commit**

```bash
git add src/plugins/discord-control.mjs src/lib/target-parser.mjs
git commit -m "discord-control: add .cmd multi-bot router"
```

---

### Task 5: Wire new handlers in main.mjs

**Files:**
- Modify: `src/main.mjs`

- [ ] **Step 1: Add new handler functions**

Add these functions to `src/main.mjs` alongside the existing `connectDiscordUser`, `disconnectDiscordUser` etc.:

```js
function getBotCount() {
  return parseInt(process.env.BOT_COUNT ?? "0", 10);
}

async function runBotActionById(botId, action) {
  return runBotAction(botId, action);
}

function getStatusById(botId) {
  const bot = getBot(botId);
  if (!bot) return { ok: false, error: "bot_not_found" };
  const server = bot.serverId ? getServer(bot.serverId) : null;
  const runtime = getBotRuntimeInfo(botId);
  return { ok: true, bot, server, runtime };
}

function setServerById(botId, host, port) {
  const serverResult = findOrCreateServerByHost(host, port);
  if (serverResult.error) return;
  updateBot(botId, { serverId: serverResult.server.id });
}

async function enableAddonById(botId, name) {
  setBotAddon(botId, name, { enabled: true });
  if (isBotRunning(botId)) {
    const state = (getBotAddons(botId) ?? {})[name] ?? {};
    const result = await enableBotAddon(botId, name, state.config);
    if (!result.ok) return { ok: false, error: result.error };
    return { ok: true, hotApplied: true };
  }
  return { ok: true, hotApplied: false };
}

function disableAddonById(botId, name) {
  setBotAddon(botId, name, { enabled: false });
  if (isBotRunning(botId)) {
    disableBotAddon(botId, name);
    return { ok: true, hotApplied: true };
  }
  return { ok: true, hotApplied: false };
}

async function runAddonCommandById(botId, addonName, sub, args) {
  return runAddonCommand(botId, addonName, sub, args);
}
```

- [ ] **Step 2: Pass new handlers to startDiscordControl**

Update the `startDiscordControl({...})` call to include the new handlers:

```js
startDiscordControl({
  authDiscordUser,
  setDiscordUserServer,
  connectDiscordUser,
  disconnectDiscordUser,
  getDiscordUserStatus,
  listDiscordUserAddons,
  enableDiscordUserAddon,
  disableDiscordUserAddon,
  runDiscordUserAddonCommand,
  // new:
  runBotActionById,
  getStatusById,
  setServerById,
  enableAddonById,
  disableAddonById,
  runAddonCommandById,
  getBotCount,
}).catch((error) => {
  console.error("[discord-control] failed to start", error);
});
```

- [ ] **Step 3: Run tests**

```bash
node --test src/lib/target-parser.test.mjs
```

Expected: all 7 pass

- [ ] **Step 4: Smoke test startup**

```bash
BOT_COUNT=3 DISCORD_ENABLED=false node src/main.mjs &
sleep 2 && kill %1
```

Expected: no errors, `[init] 3 numbered bot(s) ready`

- [ ] **Step 5: Commit**

```bash
git add src/main.mjs
git commit -m "main: wire runBotActionById + cmd handlers into startDiscordControl"
```

---

### Task 6: Update BYOB-Docker repo and push

**Files:**
- Modify: `~/byob-docker/` (separate repo)

- [ ] **Step 1: Sync source into byob-docker**

```bash
cp -r ~/build-your-own-bot/{src,package.json,pnpm-lock.yaml} ~/byob-docker/
```

- [ ] **Step 2: Update docker-compose.yml to single service**

Replace content of `~/byob-docker/docker-compose.yml`:

```yaml
services:
  bots:
    build: .
    restart: unless-stopped
    env_file: .env
    volumes:
      - ./data:/app/data
```

- [ ] **Step 3: Update .env.example**

Replace content of `~/byob-docker/.env.example`:

```
BOT_COUNT=3
DISCORD_TOKEN=
DISCORD_CHANNEL_ID=
DISCORD_SUPERUSER_IDS=
DISCORD_ENABLED=true
```

- [ ] **Step 4: Commit and push both repos**

```bash
cd ~/build-your-own-bot && git push

cd ~/byob-docker
git add .
git commit -m "Sync: single-service compose, numbered bots"
git push
```
