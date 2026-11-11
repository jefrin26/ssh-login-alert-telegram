#!/usr/bin/env bash
# Deploy SSH login alerts. Bash only.
set -euo pipefail

ALERTSCRIPT_PATH="${ALERTSCRIPT_PATH:-/opt/ssh-login-alert-telegram/alert.sh}"
PROFILE_HOOK="/etc/profile.d/telegram-alert.sh"
BEGIN_MARK="# BEGIN ssh-login-alert-telegram"
END_MARK="# END ssh-login-alert-telegram"
LEGACY_ZSHRC="/etc/zsh/zshrc"

if [ "$(id -u)" -ne 0 ]; then
    echo "Must run as root: sudo bash $0" >&2
    exit 1
fi

# Remove a previous marker block, or the old 2-line append format.
strip_block() {
    local file=$1
    [ -f "$file" ] || return 0

    local tmp
    tmp=$(mktemp) || return 1

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

    if ! cmp -s "$file" "$tmp"; then
        cat "$tmp" > "$file"
    fi
    rm -f "$tmp"
}

append_block() {
    local file=$1

    if [ -s "$file" ]; then
        if [ -n "$(tail -c 1 "$file")" ]; then
            printf '\n' >> "$file"
        fi
        printf '\n' >> "$file"
    fi

    printf '%s\n' "$BEGIN_MARK" >> "$file"
    printf '# Log connections\n' >> "$file"
    printf 'bash %s\n' "$ALERTSCRIPT_PATH" >> "$file"
    printf '%s\n' "$END_MARK" >> "$file"
}

# System-wide bash rc for interactive shells:
#   Debian/Ubuntu/Arch: /etc/bash.bashrc
#   RHEL/Fedora/openSUSE: /etc/bashrc
find_bashrc() {
    local f
    for f in /etc/bash.bashrc /etc/bashrc; do
        if [ -f "$f" ]; then
            printf '%s\n' "$f"
            return 0
        fi
    done
    return 1
}

backup_file() {
    local file=$1
    [ -f "$file" ] || return 0
    local backup="${file}.bak.$(date +%Y%m%d-%H%M%S)"
    cp -a "$file" "$backup"
    echo "  backup: $backup"
}

echo "Deploying alerts (bash only)..."

# 1. Login shells (sourced by bash via /etc/profile).
mkdir -p "$(dirname "$PROFILE_HOOK")"
cat > "$PROFILE_HOOK" <<EOF
#!/usr/bin/env bash
# Log connections
bash $ALERTSCRIPT_PATH
EOF
chmod 644 "$PROFILE_HOOK"
echo "  installed $PROFILE_HOOK"

# 2. Interactive bash shells.
if BASHRC=$(find_bashrc); then
    backup_file "$BASHRC"
    strip_block "$BASHRC"
    append_block "$BASHRC"
    echo "  installed hook in $BASHRC"
else
    echo "  WARNING: no system bash rc found (/etc/bash.bashrc or /etc/bashrc)" >&2
    echo "  interactive bash shells will not be hooked" >&2
fi

# 3. Drop any hook left by the old zsh deployment so it cannot fire twice.
if [ -f "$LEGACY_ZSHRC" ] && grep -q 'ssh-login-alert-telegram/alert\.sh' "$LEGACY_ZSHRC"; then
    backup_file "$LEGACY_ZSHRC"
    strip_block "$LEGACY_ZSHRC"
    echo "  removed legacy zsh hook from $LEGACY_ZSHRC"
fi

echo "Done!"
