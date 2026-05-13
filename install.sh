#!/usr/bin/env bash
# Install BYOB as a systemd service on a Debian/Ubuntu VPS.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/Koszwoski/Build-Your-Own-Bot---BYOB/main/install.sh | sudo bash
# or, if you already have the repo cloned:
#   sudo ./install.sh
set -euo pipefail

APP_DIR="${APP_DIR:-/root/BYOB}"
REPO_URL="${REPO_URL:-https://github.com/Koszwoski/Build-Your-Own-Bot---BYOB.git}"
NODE_MAJOR="${NODE_MAJOR:-24}"
START_SERVICE="${START_SERVICE:-true}"
SERVICE_NAME="${SERVICE_NAME:-byob}"

if [ "$(id -u)" -ne 0 ]; then
  echo "Please run as root (sudo)."
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt update
apt install -y --no-install-recommends curl git ca-certificates

if ! command -v node >/dev/null 2>&1 || ! node -e "process.exit(Number(process.versions.node.split('.')[0]) >= Number(process.env.NODE_MAJOR || '$NODE_MAJOR') ? 0 : 1)"; then
  curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" | bash -
  apt install -y --no-install-recommends nodejs
fi

corepack enable
corepack prepare pnpm@9.15.9 --activate

if [ -d "$APP_DIR/.git" ]; then
  cd "$APP_DIR"
  git pull
else
  rm -rf "$APP_DIR"
  git clone "$REPO_URL" "$APP_DIR"
  cd "$APP_DIR"
fi

pnpm install

mkdir -p "$APP_DIR/data"
if [ ! -f "$APP_DIR/data/state.json" ]; then
  cat > "$APP_DIR/data/state.json" <<'JSON'
{
  "servers": [],
  "bots": [],
  "discordLinks": {}
}
JSON
fi

if [ ! -f "$APP_DIR/.env" ]; then
  cat > "$APP_DIR/.env" <<'ENVEOF'
NODE_ENV=production
DISCORD_ENABLED=false
# DISCORD_TOKEN=...
# DISCORD_CHANNEL_ID=...
# DISCORD_ADMIN_ROLE_ID=...
# DISCORD_SUPERUSER_IDS=123456789012345678,987654321098765432
ENVEOF
  chmod 600 "$APP_DIR/.env"
fi

chmod +x "$APP_DIR/launch" "$APP_DIR/install.sh"

# Prompt for Discord config (skip if already set in .env).
prompt_env() {
  local key="$1"; local prompt="$2"; local hidden="${3:-}"
  if grep -q "^${key}=." "$APP_DIR/.env"; then return; fi
  if [ "$hidden" = "hidden" ]; then
    read -rs -p "$prompt" val; echo
  else
    read -r -p "$prompt" val
  fi
  if [ -n "$val" ]; then
    if grep -q "^${key}=" "$APP_DIR/.env"; then
      sed -i "s|^${key}=.*|${key}=${val}|" "$APP_DIR/.env"
    else
      echo "${key}=${val}" >> "$APP_DIR/.env"
    fi
  fi
}

if [ -t 0 ]; then
  echo ""
  read -r -p "Configure Discord now? (y/N) " setup_discord
  case "$setup_discord" in
    y|Y)
      prompt_env DISCORD_TOKEN "Discord bot token: " hidden
      prompt_env DISCORD_CHANNEL_ID "Discord channel ID: "
      prompt_env DISCORD_ADMIN_ROLE_ID "Discord admin role ID (empty = anyone in channel): "
      sed -i 's|^DISCORD_ENABLED=.*|DISCORD_ENABLED=true|' "$APP_DIR/.env"
      ;;
  esac
fi

cat > /etc/systemd/system/${SERVICE_NAME}.service <<SERVICEEOF
[Unit]
Description=Build-Your-Own-Bot (Discord-controlled Minecraft bot)
After=network.target

[Service]
Type=simple
WorkingDirectory=$APP_DIR
ExecStart=$APP_DIR/launch
Restart=always
RestartSec=5
EnvironmentFile=-$APP_DIR/.env
# Kernel-level RAM cap so a runaway leak can't eat the VPS.
MemoryMax=384M

[Install]
WantedBy=multi-user.target
SERVICEEOF

systemctl daemon-reload
systemctl enable ${SERVICE_NAME}.service

if [ "$START_SERVICE" = "true" ]; then
  systemctl restart ${SERVICE_NAME}.service
fi

echo ""
echo "BYOB installed."
echo "Dir:      $APP_DIR"
echo "Status:   systemctl status $SERVICE_NAME"
echo "Logs:     journalctl -u $SERVICE_NAME -f"
echo ""
echo "Discord commands:"
echo "  .auth                Microsoft login"
echo "  .server <ip> [port]  Set Minecraft server"
echo "  .connect (or .c)     Connect bot"
echo "  .status (or .s)      Show status"
echo "  .stop                Stop bot"
echo "  .addons (or .a)      List addons"
echo "  .enable <name>       Turn on addon (e.g. anti-afk)"
echo "  .disable <name>      Turn off addon"
echo "  .help                Full help"
