#!/usr/bin/env bash
# Send a Telegram alert for an SSH login. Bash only.
set -u

CONFIG="${ALERT_CONFIG:-/opt/ssh-login-alert-telegram/credentials.config}"

if [ ! -r "$CONFIG" ]; then
    echo "alert.sh: cannot read config: $CONFIG" >&2
    exit 1
fi

# shellcheck source=/dev/null
. "$CONFIG"

# HTML-escape dynamic values (pure bash, no external tools).
esc() {
    local value=$1
    value=${value//&/\&amp;}
    value=${value//</\&lt;}
    value=${value//>/\&gt;}
    printf '%s' "$value"
}

# Ignore anything that is not a real SSH session.
if [ -z "${SSH_CONNECTION:-}" ] && [ -z "${SSH_CLIENT:-}" ]; then
    exit 0
fi

# SSH_CONNECTION = "<client ip> <client port> <server ip> <server port>"
# SSH_CLIENT     = "<client ip> <client port> <server port>"
CLIENT_IP=""
CLIENT_PORT=""
SERVER_IP=""
SERVER_PORT=""

if [ -n "${SSH_CONNECTION:-}" ]; then
    read -r CLIENT_IP CLIENT_PORT SERVER_IP SERVER_PORT <<< "$SSH_CONNECTION"
elif [ -n "${SSH_CLIENT:-}" ]; then
    read -r CLIENT_IP CLIENT_PORT _ <<< "$SSH_CLIENT"
fi

if [ -z "$CLIENT_IP" ]; then
    exit 0
fi

# Send at most one alert per SSH connection, even when both the login
# profile and the interactive bash rc run for the same session.
SESSION_KEY=${SSH_CONNECTION:-${SSH_CLIENT:-}}
SESSION_KEY=${SESSION_KEY//[^A-Za-z0-9]/_}
RUNTIME_DIR=${XDG_RUNTIME_DIR:-}
if [ -z "$RUNTIME_DIR" ] || [ ! -d "$RUNTIME_DIR" ]; then
    RUNTIME_DIR=${TMPDIR:-/tmp}
fi
MARKER="${RUNTIME_DIR}/.ssh-login-alert-${UID:-0}-${SESSION_KEY}"
if mkdir -m 700 "$MARKER" 2>/dev/null; then
    : # first shell of this session
elif [ -d "$MARKER" ]; then
    exit 0 # already alerted for this session
fi

LOGIN_USER=$(id -un 2>/dev/null || printf '%s' "${USER:-unknown}")

SRV_HOSTNAME=$(hostname -f 2>/dev/null || true)
[ -n "$SRV_HOSTNAME" ] || SRV_HOSTNAME=$(hostname 2>/dev/null || true)
[ -n "$SRV_HOSTNAME" ] || SRV_HOSTNAME="unknown"

# Prefer the server address the client actually connected to.
if [ -z "$SERVER_IP" ]; then
    read -r SERVER_IP _ <<< "$(hostname -I 2>/dev/null || true)"
fi
[ -n "$SERVER_IP" ] || SERVER_IP="unknown"

DATE=$(date '+%Y-%m-%d %H:%M:%S %Z (%z)' 2>/dev/null || true)

TTY_NAME=${SSH_TTY:-}
if [ -z "$TTY_NAME" ]; then
    TTY_NAME=$(tty 2>/dev/null || true)
    [ "$TTY_NAME" = "not a tty" ] && TTY_NAME=""
fi

CLIENT_LABEL=$(esc "$CLIENT_IP")
[ -n "$CLIENT_PORT" ] && CLIENT_LABEL="${CLIENT_LABEL}:$(esc "$CLIENT_PORT")"

SERVER_LABEL=$(esc "$SERVER_IP")
[ -n "$SERVER_PORT" ] && SERVER_LABEL="${SERVER_LABEL}:$(esc "$SERVER_PORT")"

TEXT="Connection from <b>${CLIENT_LABEL}</b> as <b>$(esc "$LOGIN_USER")</b> on <b>$(esc "$SRV_HOSTNAME")</b> (<b>${SERVER_LABEL}</b>)"
TEXT+=$'\n'"Date: $(esc "$DATE")"
if [ -n "$TTY_NAME" ]; then
    TEXT+=$'\n'"TTY: $(esc "$TTY_NAME")"
fi
TEXT+=$'\n'"More information: https://ipinfo.io/$(esc "$CLIENT_IP")"

URL="https://api.telegram.org/bot${KEY}/sendMessage"

SEND_OK=0
for CHAT_ID in "${USERID[@]}"; do
    if curl -sS --max-time 15 \
        --data-urlencode "chat_id=${CHAT_ID}" \
        --data-urlencode "text=${TEXT}" \
        --data-urlencode "parse_mode=HTML" \
        --data-urlencode "disable_web_page_preview=true" \
        "$URL" > /dev/null; then
        SEND_OK=1
    else
        echo "alert.sh: failed to send alert to ${CHAT_ID}" >&2
    fi
done

# If nothing went out, drop the marker so the next shell can retry.
if [ "$SEND_OK" -eq 0 ]; then
    rmdir "$MARKER" 2>/dev/null || true
fi
