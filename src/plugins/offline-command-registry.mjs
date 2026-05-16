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

export function _resetForTest() {
  registry.clear();
}
