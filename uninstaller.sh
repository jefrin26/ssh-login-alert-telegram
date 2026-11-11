#!/usr/bin/env bash
# Uninstaller for ssh-login-alert-telegram. Bash only.
set -euo pipefail

INSTALL_DIR="/opt/ssh-login-alert-telegram"
PROFILE_HOOK="/etc/profile.d/telegram-alert.sh"
BEGIN_MARK="# BEGIN ssh-login-alert-telegram"
END_MARK="# END ssh-login-alert-telegram"
RC_FILES=(/etc/bash.bashrc /etc/bashrc /etc/zsh/zshrc)

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

# Returns 0 when the file was (or would be) changed, 1 when it was already clean.
strip_file() {
    local file=$1
    local tmp
    tmp=$(mktemp) || return 2

    awk -v b="$BEGIN_MARK" -v e="$END_MARK" '
        { line[NR] = $0 }
        END {
            for (i = 1; i <= NR; i++) {
                if (line[i] == b) { inblk = 1; del[i] = 1; continue }
                if (line[i] == e) { inblk = 0; del[i] = 1; continue }
                if (inblk) { del[i] = 1; continue }
            }
            for (i = 1; i <= NR; i++) {
                if (line[i] ~ /^bash .*ssh-login-alert-telegram\/alert\.sh$/) {
                    del[i] = 1
                    if (i > 1 && line[i-1] == "# Log connections") del[i-1] = 1
                }
            }
            for (i = 1; i <= NR; i++) if (!del[i]) print line[i]
        }
    ' "$file" > "$tmp"

    if cmp -s "$file" "$tmp"; then
        rm -f "$tmp"
        return 1
    fi

    if [ "$DRY_RUN" -eq 1 ]; then
        echo "  [dry-run] would clean $file"
        rm -f "$tmp"
        return 0
    fi

    local backup="${file}.bak.$(date +%Y%m%d-%H%M%S)"
    cp -a "$file" "$backup"
    cat "$tmp" > "$file"
    rm -f "$tmp"
    echo "  cleaned $file (backup: $backup)"
    return 0
}

echo "Uninstalling ssh-login-alert-telegram..."

# 1. Login-shell hook.
if [ -e "$PROFILE_HOOK" ]; then
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "  [dry-run] rm -f $PROFILE_HOOK"
    else
        rm -f "$PROFILE_HOOK"
        echo "  removed $PROFILE_HOOK"
    fi
else
    echo "  $PROFILE_HOOK not present, skipping"
fi

# 2. Interactive-shell hooks (bash now, zsh only for old installs).
for f in "${RC_FILES[@]}"; do
    [ -f "$f" ] || continue
    if ! strip_file "$f"; then
        echo "  no alert hook in $f"
    fi
done

# 3. Warn about references we do not own.
LEFTOVER=$(grep -Rl 'ssh-login-alert-telegram/alert\.sh' /etc 2>/dev/null \
    | grep -v -e '^/etc/bash\.bashrc$' -e '^/etc/bashrc$' -e '^/etc/zsh/zshrc$' \
        -e '^/etc/profile\.d/telegram-alert\.sh$' -e '\.bak\.' \
    || true)
if [ -n "$LEFTOVER" ]; then
    echo "  WARNING: other files still reference the alert script:"
    printf '    %s\n' $LEFTOVER
    echo "  Remove those lines manually if you added them."
fi

# 4. Optionally delete the install directory.
if [ "$PURGE" -eq 1 ]; then
    if [ -d "$INSTALL_DIR" ]; then
        if [ "$DRY_RUN" -eq 0 ] && [ "${FORCE:-0}" != "1" ]; then
            read -r -p "  Delete $INSTALL_DIR (incl. credentials.config)? [y/N] " ans || ans=""
            case "$ans" in
                [yY]*) ;;
                *) echo "  keeping $INSTALL_DIR"; PURGE=0 ;;
            esac
        fi
        if [ "$PURGE" -eq 1 ]; then
            if [ "$DRY_RUN" -eq 1 ]; then
                echo "  [dry-run] rm -rf $INSTALL_DIR"
            else
                rm -rf "$INSTALL_DIR"
                echo "  removed $INSTALL_DIR"
            fi
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
