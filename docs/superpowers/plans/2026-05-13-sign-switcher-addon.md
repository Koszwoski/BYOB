# Sign-Switcher Addon Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a generic `.addon <name> <sub> [args]` Discord command to BYOB core, then ship a standalone Sign-Switcher addon that wanders the world, breaks signs, and replaces them with random preset text.

**Architecture:** Three small changes to BYOB core (new export in mineflayer-runtime, a wrapper in main, a new command in discord-control), then a new `Sign-Switcher-Addon` repo with two files: a pure-logic preset module (fully tested) and the addon itself. The state machine (WANDERING → break → collect → place → write) runs as an async pipeline per sign found.

**Tech Stack:** Node.js ES modules, mineflayer v4, mineflayer-pathfinder v2, vec3, node:test (built-in test runner)

---

## File Map

**BYOB repo (`/home/kosz/build-your-own-bot`):**
- Modify: `src/plugins/mineflayer-runtime.mjs` — add `runAddonCommand` export
- Modify: `src/main.mjs` — add `runDiscordUserAddonCommand`, pass to `startDiscordControl`
- Modify: `src/plugins/discord-control.mjs` — add `runDiscordUserAddonCommand` param + `.addon` command handler
- Modify: `package.json` — add `mineflayer-pathfinder` dependency

**New repo (`/tmp/sign-switcher-addon`):**
- Create: `sign-switcher-presets.mjs` — pure preset I/O + matching logic (no mineflayer dep)
- Create: `sign-switcher.mjs` — the addon (state machine, sign scanning, sign writing)
- Create: `test/presets.test.mjs` — tests for all pure logic
- Create: `package.json` — ES module package with test script
- Create: `README.md` — installation guide

---

## Task 1: BYOB — Add `runAddonCommand` to mineflayer-runtime.mjs

**Files:**
- Modify: `src/plugins/mineflayer-runtime.mjs`

- [ ] **Step 1: Read the file to confirm current exports**

  Open `src/plugins/mineflayer-runtime.mjs` and confirm the last exported function (should be `stopAllBotRuntimes`).

- [ ] **Step 2: Add the export**

  Add this block at the end of `src/plugins/mineflayer-runtime.mjs`, after `stopAllBotRuntimes`:

  ```js
  export async function runAddonCommand(botId, addonName, sub, args) {
    const runtime = runningBots.get(botId);
    if (!runtime) return { ok: false, error: "bot_not_running" };
    const instance = runtime.activeAddons.get(addonName);
    if (!instance) return { ok: false, error: "addon_not_active" };
    if (typeof instance.command !== "function") return { ok: false, error: "addon_has_no_commands" };
    try {
      const result = await instance.command(sub, args);
      return { ok: true, result: String(result ?? "Done.") };
    } catch (err) {
      return { ok: false, error: err.message };
    }
  }
  ```

- [ ] **Step 3: Commit**

  ```bash
  cd /home/kosz/build-your-own-bot
  git add src/plugins/mineflayer-runtime.mjs
  git commit -m "feat: add runAddonCommand to mineflayer-runtime"
  ```

---

## Task 2: BYOB — Wire `runDiscordUserAddonCommand` in main.mjs

**Files:**
- Modify: `src/main.mjs`

- [ ] **Step 1: Add the import**

  In `src/main.mjs`, add `runAddonCommand` to the mineflayer-runtime import block:

  ```js
  import {
    disableBotAddon,
    enableBotAddon,
    getBotRuntimeInfo,
    isBotRunning,
    runAddonCommand,
    startBotRuntime,
    stopAllBotRuntimes,
    stopBotRuntime,
  } from "./plugins/mineflayer-runtime.mjs";
  ```

- [ ] **Step 2: Add the wrapper function**

  Add this function after `disableDiscordUserAddon` (around line 290 in main.mjs):

  ```js
  async function runDiscordUserAddonCommand(discordUserId, addonName, sub, args) {
    const bot = getDiscordLink(discordUserId);
    if (!bot) return { ok: false, error: "no_linked_account" };
    return runAddonCommand(bot.id, addonName, sub, args);
  }
  ```

- [ ] **Step 3: Pass it to startDiscordControl**

  Find the `startDiscordControl({` call near the bottom of main.mjs and add `runDiscordUserAddonCommand`:

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
  }).catch((error) => {
  ```

- [ ] **Step 4: Commit**

  ```bash
  git add src/main.mjs
  git commit -m "feat: wire runDiscordUserAddonCommand through main"
  ```

---

## Task 3: BYOB — Add `.addon` command to discord-control.mjs

**Files:**
- Modify: `src/plugins/discord-control.mjs`

- [ ] **Step 1: Add parameter to startDiscordControl**

  Find the `export async function startDiscordControl({` signature and add `runDiscordUserAddonCommand`:

  ```js
  export async function startDiscordControl({
    authDiscordUser,
    setDiscordUserServer,
    connectDiscordUser,
    disconnectDiscordUser,
    getDiscordUserStatus,
    listDiscordUserAddons,
    enableDiscordUserAddon,
    disableDiscordUserAddon,
    runDiscordUserAddonCommand,
  }) {
  ```

- [ ] **Step 2: Add `.addon` to helpText()**

  In the `helpText()` function, add this line inside the `"**Addons**"` section (after the `.disable` line):

  ```js
  "`.addon <name> <sub> [args]` — run an addon-specific command",
  ```

  The addons block should look like:
  ```js
  "**Addons**",
  "`.addons` (or `.a`) — list available addons",
  "`.enable <name>` (or `.e`) — turn on an addon",
  "`.disable <name>` (or `.d`) — turn off an addon",
  "`.addon <name> <sub> [args]` — run an addon-specific command",
  ```

- [ ] **Step 3: Add the command handler**

  In the `messageCreate` handler, add this block after the `disable` command block (around the `if (command === "disable" || command === "d")` block), just before the final `await message.reply(helpText())`:

  ```js
  if (command === "addon") {
    const [addonName, sub, ...addonArgs] = args;
    if (!addonName || !sub) {
      await message.reply("Usage: `.addon <name> <subcommand> [args...]`");
      return;
    }
    if (!runDiscordUserAddonCommand) {
      await message.reply("Addon command system not wired up.");
      return;
    }
    const result = await runDiscordUserAddonCommand(discordUserId, addonName, sub, addonArgs);
    if (!result.ok) {
      await message.reply(`Addon command failed: \`${result.error}\``);
      return;
    }
    await message.reply(result.result);
    return;
  }
  ```

- [ ] **Step 4: Commit**

  ```bash
  git add src/plugins/discord-control.mjs
  git commit -m "feat: add .addon command to discord-control"
  ```

---

## Task 4: BYOB — Add mineflayer-pathfinder dependency

**Files:**
- Modify: `package.json`

- [ ] **Step 1: Add the dependency**

  ```bash
  cd /home/kosz/build-your-own-bot
  pnpm add mineflayer-pathfinder
  ```

  Expected output: mineflayer-pathfinder added to package.json and pnpm-lock.yaml.

- [ ] **Step 2: Commit**

  ```bash
  git add package.json pnpm-lock.yaml
  git commit -m "deps: add mineflayer-pathfinder"
  ```

- [ ] **Step 3: Push all BYOB changes**

  ```bash
  git push origin main
  ```

---

## Task 5: Sign-Switcher-Addon — Repository setup

- [ ] **Step 1: Create local directory and git repo**

  ```bash
  mkdir -p /tmp/sign-switcher-addon/test
  cd /tmp/sign-switcher-addon
  git init
  git checkout -b main
  git remote add origin https://github.com/Koszwoski/Sign-Switcher-Addon.git
  ```

- [ ] **Step 2: Create package.json**

  Create `/tmp/sign-switcher-addon/package.json`:

  ```json
  {
    "name": "sign-switcher-addon",
    "version": "1.0.0",
    "type": "module",
    "engines": { "node": ">=20" },
    "scripts": {
      "test": "node --test test/presets.test.mjs"
    },
    "peerDependencies": {
      "mineflayer": ">=4",
      "mineflayer-pathfinder": ">=2",
      "vec3": ">=0.1"
    }
  }
  ```

---

## Task 6: Sign-Switcher-Addon — Pure preset logic (TDD)

**Files:**
- Create: `sign-switcher-presets.mjs`
- Create: `test/presets.test.mjs`

- [ ] **Step 1: Write the failing tests**

  Create `/tmp/sign-switcher-addon/test/presets.test.mjs`:

  ```js
  import { test } from 'node:test';
  import assert from 'node:assert/strict';
  import { tmpdir } from 'node:os';
  import { join } from 'node:path';
  import { loadPresets, savePresets, matchesAnyPreset, getRandomPreset } from '../sign-switcher-presets.mjs';

  test('loadPresets returns {} for missing file', async () => {
    const result = await loadPresets(join(tmpdir(), `ss-nonexistent-${Date.now()}.json`));
    assert.deepEqual(result, {});
  });

  test('savePresets then loadPresets roundtrips data', async () => {
    const filePath = join(tmpdir(), `ss-test-${Date.now()}.json`);
    const presets = { Hello: ['Hello', 'World', '', ''] };
    await savePresets(presets, filePath);
    const loaded = await loadPresets(filePath);
    assert.deepEqual(loaded, presets);
  });

  test('matchesAnyPreset returns true when lines match a preset exactly', () => {
    const presets = { A: ['Hello', 'World', '', ''] };
    assert.equal(matchesAnyPreset(['Hello', 'World', '', ''], presets), true);
  });

  test('matchesAnyPreset returns false when a line differs', () => {
    const presets = { A: ['Hello', 'World', '', ''] };
    assert.equal(matchesAnyPreset(['Hello', 'Other', '', ''], presets), false);
  });

  test('matchesAnyPreset returns false for empty preset map', () => {
    assert.equal(matchesAnyPreset(['Hello', 'World', '', ''], {}), false);
  });

  test('matchesAnyPreset treats missing lines as empty string', () => {
    const presets = { A: ['Hi', '', '', ''] };
    assert.equal(matchesAnyPreset(['Hi', '', '', ''], presets), true);
    assert.equal(matchesAnyPreset(['Hi', 'extra', '', ''], presets), false);
  });

  test('matchesAnyPreset matches any preset in the map', () => {
    const presets = { A: ['foo', '', '', ''], B: ['bar', '', '', ''] };
    assert.equal(matchesAnyPreset(['bar', '', '', ''], presets), true);
  });

  test('getRandomPreset returns null for empty presets', () => {
    assert.equal(getRandomPreset({}), null);
  });

  test('getRandomPreset returns an array of 4 strings', () => {
    const presets = { A: ['a', 'b', 'c', 'd'] };
    const result = getRandomPreset(presets);
    assert.ok(Array.isArray(result));
    assert.equal(result.length, 4);
  });

  test('getRandomPreset returns only presets that exist in the map', () => {
    const presets = { A: ['a', '', '', ''], B: ['b', '', '', ''] };
    for (let i = 0; i < 20; i++) {
      const result = getRandomPreset(presets);
      assert.ok(result === presets.A || result === presets.B);
    }
  });
  ```

- [ ] **Step 2: Run tests — expect failure (module not found)**

  ```bash
  cd /tmp/sign-switcher-addon
  node --test test/presets.test.mjs 2>&1 | head -20
  ```

  Expected: error like `Cannot find module '../sign-switcher-presets.mjs'`

- [ ] **Step 3: Create sign-switcher-presets.mjs**

  Create `/tmp/sign-switcher-addon/sign-switcher-presets.mjs`:

  ```js
  import { promises as fs } from 'node:fs';
  import path from 'node:path';

  export const DEFAULT_PATH = path.join(process.cwd(), 'data', 'sign-switcher-presets.json');

  export async function loadPresets(filePath = DEFAULT_PATH) {
    try {
      const raw = await fs.readFile(filePath, 'utf8');
      return JSON.parse(raw).presets ?? {};
    } catch {
      return {};
    }
  }

  export async function savePresets(presets, filePath = DEFAULT_PATH) {
    await fs.mkdir(path.dirname(filePath), { recursive: true });
    await fs.writeFile(filePath, JSON.stringify({ presets }, null, 2));
  }

  export function matchesAnyPreset(lines, presets) {
    return Object.values(presets).some(
      (preset) =>
        preset.length === 4 &&
        preset.every((line, i) => (line ?? '') === (lines[i] ?? ''))
    );
  }

  export function getRandomPreset(presets) {
    const values = Object.values(presets);
    if (!values.length) return null;
    return values[Math.floor(Math.random() * values.length)];
  }
  ```

- [ ] **Step 4: Run tests — expect all pass**

  ```bash
  cd /tmp/sign-switcher-addon
  node --test test/presets.test.mjs
  ```

  Expected: all 10 tests pass, no failures.

- [ ] **Step 5: Commit**

  ```bash
  cd /tmp/sign-switcher-addon
  git add sign-switcher-presets.mjs test/presets.test.mjs package.json
  git commit -m "feat: add preset logic with full test coverage"
  ```

---

## Task 7: Sign-Switcher-Addon — Main addon file

**Files:**
- Create: `sign-switcher.mjs`

- [ ] **Step 1: Create sign-switcher.mjs**

  Create `/tmp/sign-switcher-addon/sign-switcher.mjs`:

  ```js
  import { pathfinder, Movements, goals } from 'mineflayer-pathfinder';
  import { Vec3 } from 'vec3';
  import {
    loadPresets,
    savePresets,
    matchesAnyPreset,
    getRandomPreset,
  } from './sign-switcher-presets.mjs';

  const { GoalNear } = goals;

  export const meta = {
    name: 'sign-switcher',
    description: 'Wanders and replaces signs with random preset text.',
    defaultConfig: {
      scanIntervalTicks: 20,
      wanderRange: 100,
      writeDelayMs: 250,
    },
  };

  export function init(bot, config, ctx) {
    const log = ctx?.log ?? (() => {});

    bot.loadPlugin(pathfinder);

    let presets = {};
    let busy = false;
    let stopped = false;
    let scanTick = 0;
    let tickTimer = null;

    // Cache sign text from block entity packets for loop prevention
    const signTextCache = new Map();
    bot._client.on('block_entity_data', (packet) => {
      const { x, y, z } = packet.location;
      const nbt = packet.nbtData;
      if (!nbt) return;
      const frontText = nbt.value?.front_text?.value;
      if (!frontText) return;
      const msgs = frontText.messages?.value?.value ?? [];
      const lines = msgs.map((m) => {
        try { return JSON.parse(m.value ?? m).text ?? ''; } catch { return ''; }
      });
      signTextCache.set(`${x},${y},${z}`, lines);
    });

    async function reloadPresets() {
      presets = await loadPresets();
    }

    function startWander() {
      if (stopped) return;
      const pos = bot.entity.position;
      const range = config.wanderRange ?? 100;
      const x = Math.floor(pos.x) + Math.floor(Math.random() * (range * 2 + 1)) - range;
      const z = Math.floor(pos.z) + Math.floor(Math.random() * (range * 2 + 1)) - range;
      bot.pathfinder.setGoal(new GoalNear(x, Math.floor(pos.y), z, 3));
    }

    function findNearbySign() {
      if (!Object.keys(presets).length) return null;
      const block = bot.findBlock({
        matching: (b) => b.name.includes('sign'),
        maxDistance: 64,
      });
      if (!block) return null;
      const key = `${block.position.x},${block.position.y},${block.position.z}`;
      const lines = signTextCache.get(key) ?? [];
      if (matchesAnyPreset(lines, presets)) return null;
      // Only target floor-standing signs (solid block directly below)
      const below = bot.blockAt(block.position.offset(0, -1, 0));
      if (!below || below.name === 'air') return null;
      return block.position;
    }

    function waitForInventorySign(timeoutMs) {
      return new Promise((resolve) => {
        if (bot.inventory.items().some((i) => i.name.includes('sign'))) {
          resolve(true);
          return;
        }
        const timer = setTimeout(() => {
          bot.removeListener('playerCollect', handler);
          resolve(false);
        }, timeoutMs);
        function handler() {
          if (bot.inventory.items().some((i) => i.name.includes('sign'))) {
            clearTimeout(timer);
            bot.removeListener('playerCollect', handler);
            resolve(true);
          }
        }
        bot.on('playerCollect', handler);
      });
    }

    async function runPipeline(targetPos) {
      busy = true;
      try {
        log(`[sign-switcher] approaching sign at ${targetPos}`);

        // Navigate to sign
        await bot.pathfinder.goto(new GoalNear(targetPos.x, targetPos.y, targetPos.z, 3));
        if (stopped) return;

        // Break sign
        const signBlock = bot.blockAt(targetPos);
        if (!signBlock?.name.includes('sign')) {
          log('[sign-switcher] sign gone before break');
          return;
        }
        await bot.dig(signBlock);
        if (stopped) return;

        // Collect — wait up to 5s for sign to appear in inventory
        await waitForInventorySign(5000);
        if (stopped) return;

        const signItem = bot.inventory.items().find((i) => i.name.includes('sign'));
        if (!signItem) {
          log('[sign-switcher] no sign in inventory after break');
          return;
        }

        // Navigate back to placement position
        await bot.pathfinder.goto(new GoalNear(targetPos.x, targetPos.y, targetPos.z, 3));
        if (stopped) return;

        // Place sign on the block below the original position
        const refBlock = bot.blockAt(targetPos.offset(0, -1, 0));
        if (!refBlock || refBlock.name === 'air') {
          log('[sign-switcher] no block to place sign on');
          return;
        }
        await bot.equip(signItem, 'hand');
        await bot.placeBlock(refBlock, new Vec3(0, 1, 0));
        if (stopped) return;

        // Write text after a short delay
        await new Promise((r) => setTimeout(r, config.writeDelayMs ?? 250));
        if (stopped) return;

        const placedSign = bot.blockAt(targetPos);
        if (!placedSign?.name.includes('sign')) {
          log('[sign-switcher] sign not found after place');
          return;
        }
        const preset = getRandomPreset(presets);
        if (preset) {
          await bot.updateSign(placedSign, preset, true);
          log(`[sign-switcher] replaced sign at ${targetPos}`);
        }
      } catch (err) {
        log(`[sign-switcher] pipeline error: ${err.message}`);
      } finally {
        busy = false;
      }
    }

    function tick() {
      if (stopped || busy) return;
      if (!bot.pathfinder.isMoving()) startWander();
      if (++scanTick >= (config.scanIntervalTicks ?? 20)) {
        scanTick = 0;
        const target = findNearbySign();
        if (target) {
          bot.pathfinder.stop();
          runPipeline(target);
        }
      }
    }

    reloadPresets().then(() => {
      if (stopped) return;
      const movements = new Movements(bot);
      bot.pathfinder.setMovements(movements);
      startWander();
      tickTimer = setInterval(tick, 50);
    });

    return {
      cleanup() {
        stopped = true;
        clearInterval(tickTimer);
        try { bot.pathfinder.stop(); } catch {}
      },

      async command(sub, args) {
        await reloadPresets();

        if (sub === 'add') {
          const [name, l1, l2, l3, l4] = args;
          if (!name) return 'Usage: `.addon sign-switcher add <name> <l1> <l2> <l3> <l4>`';
          presets[name] = [l1 ?? '', l2 ?? '', l3 ?? '', l4 ?? ''];
          await savePresets(presets);
          return `Preset \`${name}\` saved: "${l1 ?? ''}" / "${l2 ?? ''}" / "${l3 ?? ''}" / "${l4 ?? ''}"`;
        }

        if (sub === 'remove') {
          const [name] = args;
          if (!name) return 'Usage: `.addon sign-switcher remove <name>`';
          if (!presets[name]) return `Preset \`${name}\` not found.`;
          delete presets[name];
          await savePresets(presets);
          return `Preset \`${name}\` removed.`;
        }

        if (sub === 'list') {
          const names = Object.keys(presets);
          if (!names.length) return 'No presets. Use `.addon sign-switcher add <name> <l1> <l2> <l3> <l4>`';
          return `Presets (${names.length}): ${names.map((n) => `\`${n}\``).join(', ')}`;
        }

        return `Unknown subcommand \`${sub}\`. Available: add, remove, list`;
      },
    };
  }
  ```

- [ ] **Step 2: Commit**

  ```bash
  cd /tmp/sign-switcher-addon
  git add sign-switcher.mjs
  git commit -m "feat: add sign-switcher addon with state machine"
  ```

---

## Task 8: Sign-Switcher-Addon — README

**Files:**
- Create: `README.md`

- [ ] **Step 1: Create README.md**

  Create `/tmp/sign-switcher-addon/README.md`:

  ```markdown
  # Sign-Switcher Addon for BYOB

  Wanders the world, breaks signs, and replaces them with random text from your preset list. Only replaces signs whose current text does not already match a preset.

  ## Installation

  1. Copy `sign-switcher.mjs` and `sign-switcher-presets.mjs` into BYOB's `src/addons/` folder.
  2. Add `"sign-switcher"` to the `AVAILABLE` array in `src/addons/index.mjs`.
  3. In your BYOB directory, install the pathfinding dependency:
     ```bash
     pnpm add mineflayer-pathfinder
     ```
     (Skip this step if BYOB already has `mineflayer-pathfinder` in its `package.json`.)
  4. Restart the bot and enable with `.enable sign-switcher` in Discord.

  ## Discord Commands

  All commands go through the `.addon` system:

  | Command | Description |
  |---|---|
  | `.addon sign-switcher add <name> <l1> <l2> <l3> <l4>` | Add or overwrite a preset |
  | `.addon sign-switcher remove <name>` | Remove a preset |
  | `.addon sign-switcher list` | List all preset names |

  ### Example

  ```
  .addon sign-switcher add Greeting "Hello!" "Welcome" "" ""
  .addon sign-switcher add Warning "Keep out" "" "" ""
  .addon sign-switcher list
  ```

  ## How It Works

  1. The bot wanders randomly within ±100 blocks.
  2. Every second it scans for signs within 64 blocks.
  3. Signs already matching a preset are skipped (loop prevention).
  4. When a matching sign is found: navigate → break → collect → place → write.
  5. A random preset is chosen for each replaced sign.

  ## Config

  | Key | Default | Description |
  |---|---|---|
  | `scanIntervalTicks` | `20` | Ticks between sign scans (50ms each, 20 = 1 second) |
  | `wanderRange` | `100` | Max wander distance in blocks |
  | `writeDelayMs` | `250` | Delay after placing before writing text |

  ## Notes

  - Only floor-standing signs are supported (wall-mounted signs are skipped).
  - Presets are stored in `data/sign-switcher-presets.json` in the BYOB working directory and persist across restarts.
  - The addon must be active (bot running + `.enable sign-switcher`) before `.addon sign-switcher` commands work.
  ```

- [ ] **Step 2: Commit**

  ```bash
  cd /tmp/sign-switcher-addon
  git add README.md
  git commit -m "docs: add README with installation and usage"
  ```

---

## Task 9: Create GitHub repo and push

- [ ] **Step 1: Create the GitHub repo**

  ```bash
  gh repo create Koszwoski/Sign-Switcher-Addon --public --description "Sign switcher addon for BYOB (Build Your Own Bot)"
  ```

- [ ] **Step 2: Push**

  ```bash
  cd /tmp/sign-switcher-addon
  git push -u origin main
  ```

  Expected: all commits pushed, repo live at `https://github.com/Koszwoski/Sign-Switcher-Addon`

---

## Self-Review Checklist

- [x] `.addon` command in discord-control — covered in Task 3
- [x] `runAddonCommand` export — covered in Task 1
- [x] `runDiscordUserAddonCommand` wrapper — covered in Task 2
- [x] mineflayer-pathfinder dependency — covered in Task 4
- [x] Preset add/remove/list — covered in Task 6 + 7
- [x] Loop prevention via sign text cache — in Task 7 (`signTextCache`, `matchesAnyPreset`)
- [x] State machine WANDERING → BREAKING → COLLECTING → PLACING → WRITING — in Task 7
- [x] cleanup() stops pathfinder and interval — in Task 7
- [x] `command()` returns string for Discord — in Task 7
- [x] Tests for all pure logic — in Task 6 (10 tests)
- [x] Both files (`sign-switcher.mjs` + `sign-switcher-presets.mjs`) mentioned in README install steps
