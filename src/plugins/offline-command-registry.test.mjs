import assert from 'node:assert/strict';
import { test } from 'node:test';
import {
  registerCommand,
  unregisterCommand,
  getCommand,
  _resetForTest,
} from './offline-command-registry.mjs';

test('getCommand returns null for unknown botId', () => {
  _resetForTest();
  assert.equal(getCommand('no-such-bot', 'sign-switcher'), null);
});

test('getCommand returns null for unknown addonName', () => {
  _resetForTest();
  const fn = () => 'ok';
  registerCommand('bot1', 'sign-switcher', fn);
  assert.equal(getCommand('bot1', 'no-such-addon'), null);
});

test('registerCommand then getCommand returns the function', () => {
  _resetForTest();
  const fn = () => 'result';
  registerCommand('bot2', 'sign-switcher', fn);
  assert.equal(getCommand('bot2', 'sign-switcher'), fn);
});

test('unregisterCommand removes the entry', () => {
  _resetForTest();
  const fn = () => 'x';
  registerCommand('bot3', 'sign-switcher', fn);
  unregisterCommand('bot3', 'sign-switcher');
  assert.equal(getCommand('bot3', 'sign-switcher'), null);
});

test('unregisterCommand on nonexistent entry does not throw', () => {
  _resetForTest();
  assert.doesNotThrow(() => unregisterCommand('bot-ghost', 'sign-switcher'));
});

test('registerCommand overwrites previous entry for same botId+addonName', () => {
  _resetForTest();
  const fn1 = () => 'first';
  const fn2 = () => 'second';
  registerCommand('bot4', 'sign-switcher', fn1);
  registerCommand('bot4', 'sign-switcher', fn2);
  assert.equal(getCommand('bot4', 'sign-switcher'), fn2);
});

test('multiple addons under the same botId are stored independently', () => {
  _resetForTest();
  const fn1 = () => 'addon-a';
  const fn2 = () => 'addon-b';
  registerCommand('botX', 'addon-a', fn1);
  registerCommand('botX', 'addon-b', fn2);
  assert.equal(getCommand('botX', 'addon-a'), fn1);
  assert.equal(getCommand('botX', 'addon-b'), fn2);
});
