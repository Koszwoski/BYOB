# Offline Addon Commands Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Allow addon commands to run even when the bot is disconnected, by caching each addon's `command()` function when it loads.

**Architecture:** Extract a pure `offline-command-registry` module (add/get/remove by botId + addonName) so the logic is testable in isolation. `mineflayer-runtime.mjs` calls the registry when loading/disabling addons and falls back to it when the bot is offline.

**Tech Stack:** Node.js ESM, `node:test`, `node:assert/strict`

---

## File Map

| File | Change |
|---|---|
| `src/plugins/offline-command-registry.mjs` | **Create** — pure registry: register, unregister, get |
| `src/plugins/offline-command-registry.test.mjs` | **Create** — 6 tests for the registry |
| `src/plugins/mineflayer-runtime.mjs` | **Modify** — import registry, call register/unregister/get |

---

### Task 1: Create offline-command-registry with tests (TDD)

**Files:**
- Create: `src/plugins/offline-command-registry.mjs`
- Create: `src/plugins/offline-command-registry.test.mjs`

- [ ] **Step 1: Write the failing tests**

Create `src/plugins/offline-command-registry.test.mjs`:

```js
import assert from 'node:assert/strict';
import { test } from 'node:test';
import {
  registerCommand,
  unregisterCommand,
  getCommand,
} from './offline-command-registry.mjs';

test('getCommand returns null for unknown botId', () => {
  assert.equal(getCommand('no-such-bot', 'sign-switcher'), null);
});

test('getCommand returns null for unknown addonName', () => {
  const fn = () => 'ok';
  registerCommand('bot1', 'sign-switcher', fn);
  assert.equal(getCommand('bot1', 'no-such-addon'), null);
});

test('registerCommand then getCommand returns the function', () => {
  const fn = () => 'result';
  registerCommand('bot2', 'sign-switcher', fn);
  assert.equal(getCommand('bot2', 'sign-switcher'), fn);
});

test('unregisterCommand removes the entry', () => {
  const fn = () => 'x';
  registerCommand('bot3', 'sign-switcher', fn);
  unregisterCommand('bot3', 'sign-switcher');
  assert.equal(getCommand('bot3', 'sign-switcher'), null);
});

test('unregisterCommand on nonexistent entry does not throw', () => {
  assert.doesNotThrow(() => unregisterCommand('bot-ghost', 'sign-switcher'));
});

test('registerCommand overwrites previous entry for same botId+addonName', () => {
  const fn1 = () => 'first';
  const fn2 = () => 'second';
  registerCommand('bot4', 'sign-switcher', fn1);
  registerCommand('bot4', 'sign-switcher', fn2);
  assert.equal(getCommand('bot4', 'sign-switcher'), fn2);
});
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd /home/kosz/build-your-own-bot && node --test src/plugins/offline-command-registry.test.mjs
```

Expected: all 6 tests fail with `Error [ERR_MODULE_NOT_FOUND]` or similar.

- [ ] **Step 3: Implement `offline-command-registry.mjs`**

Create `src/plugins/offline-command-registry.mjs`:

```js
const registry = new Map(); // Map<botId, Map<addonName, commandFn>>

export function registerCommand(botId, addonName, commandFn) {
  if (!registry.has(botId)) registry.set(botId, new Map());
  registry.get(botId).set(addonName, commandFn);
}

export function unregisterCommand(botId, addonName) {
  registry.get(botId)?.delete(addonName);
}

export function getCommand(botId, addonName) {
  return registry.get(botId)?.get(addonName) ?? null;
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd /home/kosz/build-your-own-bot && node --test src/plugins/offline-command-registry.test.mjs
```

Expected: all 6 tests pass, 0 failures.

- [ ] **Step 5: Commit**

```bash
cd /home/kosz/build-your-own-bot
git add src/plugins/offline-command-registry.mjs src/plugins/offline-command-registry.test.mjs
git commit -m "feat: add offline-command-registry for addon commands while bot is offline"
```

---

### Task 2: Integrate registry into mineflayer-runtime

**Files:**
- Modify: `src/plugins/mineflayer-runtime.mjs`

- [ ] **Step 1: Add the import at the top of `mineflayer-runtime.mjs`**

Find the first line of `src/plugins/mineflayer-runtime.mjs`:

```js
import { instantiateAddon } from "../addons/index.mjs";
```

Replace with:

```js
import { instantiateAddon } from "../addons/index.mjs";
import { registerCommand, unregisterCommand, getCommand } from "./offline-command-registry.mjs";
```

- [ ] **Step 2: Register command in `loadAddonForRuntime`**

Find `loadAddonForRuntime` (currently lines 55–60):

```js
async function loadAddonForRuntime(runtime, name, userConfig, onLog) {
  const ctx = { botId: runtime.botId, log: onLog };
  const instance = await instantiateAddon(name, runtime.mineflayerBot, userConfig, ctx);
  runtime.activeAddons.set(name, instance);
  return instance;
}
```

Replace with:

```js
async function loadAddonForRuntime(runtime, name, userConfig, onLog) {
  const ctx = { botId: runtime.botId, log: onLog };
  const instance = await instantiateAddon(name, runtime.mineflayerBot, userConfig, ctx);
  runtime.activeAddons.set(name, instance);
  if (typeof instance.command === 'function') {
    registerCommand(runtime.botId, name, instance.command.bind(instance));
  }
  return instance;
}
```

- [ ] **Step 3: Unregister command in `disableBotAddon`**

Find `disableBotAddon` (currently lines 85–90):

```js
export function disableBotAddon(botId, name, onLog = console.log) {
  const runtime = runningBots.get(botId);
  if (!runtime) return { ok: false, error: "bot_not_running" };
  const removed = unloadAddonFromRuntime(runtime, name, onLog);
  return { ok: true, wasActive: removed };
}
```

Replace with:

```js
export function disableBotAddon(botId, name, onLog = console.log) {
  const runtime = runningBots.get(botId);
  if (!runtime) return { ok: false, error: "bot_not_running" };
  const removed = unloadAddonFromRuntime(runtime, name, onLog);
  unregisterCommand(botId, name);
  return { ok: true, wasActive: removed };
}
```

- [ ] **Step 4: Add offline fallback in `runAddonCommand`**

Find `runAddonCommand` (currently lines 216–228):

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

Replace with:

```js
export async function runAddonCommand(botId, addonName, sub, args) {
  const runtime = runningBots.get(botId);
  if (!runtime) {
    const commandFn = getCommand(botId, addonName);
    if (!commandFn) return { ok: false, error: "bot_not_running" };
    try {
      const result = await commandFn(sub, args);
      return { ok: true, result: String(result ?? "Done.") };
    } catch (err) {
      return { ok: false, error: err.message };
    }
  }
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

- [ ] **Step 5: Run the registry tests to confirm nothing regressed**

```bash
cd /home/kosz/build-your-own-bot && node --test src/plugins/offline-command-registry.test.mjs
```

Expected: all 6 tests pass.

- [ ] **Step 6: Commit**

```bash
cd /home/kosz/build-your-own-bot
git add src/plugins/mineflayer-runtime.mjs
git commit -m "feat: cache addon commands so they work while bot is offline"
```

---

### Task 3: Push to GitHub

- [ ] **Step 1: Push**

```bash
cd /home/kosz/build-your-own-bot && git push
```

Expected: `main -> main` with the two new commits.
