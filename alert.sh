#!/usr/bin/env bash

# Import credentials from config file
. /opt/ssh-login-alert-telegram/credentials.config

# HTML-escape dynamic values so hostnames/usernames with & < > can't break parsing
esc() { printf '%s' "$1" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g'; }

for i in "${USERID[@]}"
do
    URL="https://api.telegram.org/bot${KEY}/sendMessage"
    DATE="$(date '+%d %b %Y %H:%M')"
    TZ_NAME="$(date '+%Z')"

    if [ -n "$SSH_CLIENT" ]; then
        CLIENT_IP=$(echo "$SSH_CLIENT" | awk '{print $1}')

        SRV_HOSTNAME=$(hostname -f 2>/dev/null)
        [ -z "$SRV_HOSTNAME" ] && SRV_HOSTNAME=$(hostname)
        SRV_IP=$(hostname -I | awk '{print $1}')

        IPINFO="https://ipinfo.io/${CLIENT_IP}"

        TEXT="Connection from <b>$(esc "$CLIENT_IP")</b> as <b>$(esc "$USER")</b> on <b>$(esc "$SRV_HOSTNAME")</b> (<b>$(esc "$SRV_IP")</b>)
Date: ${DATE} ${TZ_NAME}
More information: ${IPINFO}"

        curl -s -d "chat_id=$i&text=${TEXT}&disable_web_page_preview=true&parse_mode=HTML" "$URL" > /dev/null
    fi
done
