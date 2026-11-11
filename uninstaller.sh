#!/usr/bin/env bash
# Uninstaller for ssh-login-alert-telegram
set -euo pipefail

INSTALL_DIR="/opt/ssh-login-alert-telegram"
PROFILE_HOOK="/etc/profile.d/telegram-alert.sh"
ZSHRC="/etc/zsh/zshrc"
BACKUP="${ZSHRC}.bak.$(date +%Y%m%d-%H%M%S)"

DRY_RUN=0
PURGE=0

usage() {
  cat <<EOF
Usage: sudo bash uninstaller.sh [--dry-run] [--purge]

  --dry-run   Show what would be removed, change nothing
  --purge     Also delete $INSTALL_DIR (contains credentials.config)
  -h, --help  Show this help
EOF
}

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --purge)   PURGE=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; usage >&2; exit 2 ;;
  esac
done

if [ "$DRY_RUN" -eq 0 ] && [ "$(id -u)" -ne 0 ]; then
  echo "Must run as root: sudo bash $0" >&2
  exit 1
fi

run() {
  if [ "$DRY_RUN" -eq 1 ]; then echo "[dry-run] $*"; else "$@"; fi
}

echo "Uninstalling ssh-login-alert-telegram..."

# 1. profile.d hook (bash/sh/zsh logins on most distros)
if [ -e "$PROFILE_HOOK" ]; then
  run rm -f "$PROFILE_HOOK"
  echo "  removed $PROFILE_HOOK"
else
  echo "  $PROFILE_HOOK not present, skipping"
fi

# 2. Remove the appended block from /etc/zsh/zshrc
if [ -f "$ZSHRC" ] && grep -q 'ssh-login-alert-telegram/alert\.sh' "$ZSHRC"; then
  TMP="$(mktemp)"
  trap 'rm -f "$TMP"' EXIT

  awk '
    { line[NR] = $0 }
    END {
      for (i = 1; i <= NR; i++) {
        if (line[i] ~ /^bash .*ssh-login-alert-telegram\/alert\.sh$/) {
          del[i] = 1
          if (i > 1 && line[i-1] == "# Log connections") del[i-1] = 1
        }
      }
      for (i = 1; i <= NR; i++) if (!del[i]) print line[i]
    }
  ' "$ZSHRC" > "$TMP"

  if cmp -s "$ZSHRC" "$TMP"; then
    echo "  no matching zsh lines, leaving $ZSHRC untouched"
  else
    run cp -a "$ZSHRC" "$BACKUP"
    run cp "$TMP" "$ZSHRC"
    echo "  cleaned $ZSHRC (backup: $BACKUP)"
  fi
else
  echo "  no zsh hook found, skipping"
fi

# 3. Warn about references we do not own
LEFTOVER="$(grep -Rl 'ssh-login-alert-telegram/alert\.sh' /etc 2>/dev/null \
            | grep -v "^$ZSHRC" || true)"
if [ -n "$LEFTOVER" ]; then
  echo "  WARNING: other files still reference the alert script:"
  printf '    %s\n' $LEFTOVER
  echo "  Remove those lines manually if you added them."
fi

# 4. Optionally delete the install directory
if [ "$PURGE" -eq 1 ]; then
  if [ -d "$INSTALL_DIR" ]; then
    if [ "$DRY_RUN" -eq 0 ] && [ "${FORCE:-0}" != "1" ]; then
      read -r -p "  Delete $INSTALL_DIR (incl. credentials.config)? [y/N] " ans || ans=""
      case "$ans" in [yY]*) ;; *) echo "  keeping $INSTALL_DIR"; PURGE=0 ;; esac
    fi
    if [ "$PURGE" -eq 1 ]; then
      run rm -rf "$INSTALL_DIR"
      echo "  removed $INSTALL_DIR"
    fi
  else
    echo "  $INSTALL_DIR not present, skipping"
  fi
else
  echo "  kept $INSTALL_DIR (use --purge to delete it)"
fi

echo "Done. New SSH logins will no longer trigger alerts."
echo "Active sessions are unaffected."
echo "Revoke the bot token in @BotFather if credentials.config was exposed."
