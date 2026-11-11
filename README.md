## Alert via telegram when user logon via SSH

Work on all popular linux system (Debian, Ubuntu, Arch Linux etc..)

Uses **bash only** — no zsh or other shells required.

![Example](msg.png)

### Requirement
- bash
- curl
- git (much easy to install)

### Install
1) Clone or download to /opt/ folder
```cd /opt/ && git clone https://github.com/vdeville/ssh-login-alert-telegram```

2) Edit two configuration variables by editing credentials.config:
```vim credentials.config```

3) Add this script when user connect with the deploy script:
```sudo bash deploy.sh```

The deploy script hooks bash in two places:
- `/etc/profile.d/telegram-alert.sh` for login shells
- `/etc/bash.bashrc` (or `/etc/bashrc`) for interactive shells

It is safe to re-run: existing hooks are replaced, not duplicated, and any hook
left by the old zsh deployment is removed. `alert.sh` sends at most one alert
per SSH connection, so both hooks cannot double-alert.

4) Confirm that the script is working by logging you to ssh again.

### Uninstall
Run the uninstaller as root:
```sudo bash uninstaller.sh```

To also delete the install directory (including `credentials.config`):
```sudo bash uninstaller.sh --purge```

Use `--dry-run` to preview the changes without touching anything. A timestamped
backup of every modified shell rc file is created before it is changed.

### Install with Ansible

If you have many servers go check: https://github.com/vdeville/Deploy-Telegram-SSH-Alerting-with-Ansible (fork of initial @stylernico work)
