// Anti-AFK: briefly toggles a control state on a fixed interval so
// the player is registered as active. Cheap - no chunk loading, no
// pathfinding, just a setInterval + two control-state toggles.
//
// Config:
//   intervalMs: how often to fire (default 30s)
//   action:     "sneak" | "jump" | "swing"  (default "sneak")

export const meta = {
  name: "anti-afk",
  description: "Periodically sneak/jump/swing so the server does not flag the bot as AFK.",
  defaultConfig: {
    intervalMs: 30000,
    action: "sneak",
  },
};

export function init(bot, config, ctx) {
  const action = ["sneak", "jump", "swing"].includes(config.action) ? config.action : "sneak";
  const intervalMs = Math.max(2000, Number(config.intervalMs) || 30000);

  const log = ctx?.log ?? (() => {});
  log(`[anti-afk] active for ${ctx?.botId ?? "?"}: ${action} every ${intervalMs}ms`);

  function tick() {
    try {
      if (action === "swing") {
        bot.swingArm("right");
        return;
      }
      bot.setControlState(action, true);
      setTimeout(() => {
        try { bot.setControlState(action, false); } catch {}
      }, 200);
    } catch (err) {
      log(`[anti-afk] tick failed: ${err.message}`);
    }
  }

  const timer = setInterval(tick, intervalMs);

  return {
    cleanup() {
      clearInterval(timer);
      try { bot.setControlState(action, false); } catch {}
    },
  };
}
