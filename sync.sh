#!/bin/bash
# Colors

ROM_DIR="$(pwd)"
export $(grep -vE '^\s*(#|$)' "$ROM_DIR/vars.txt")

# Send TG msg
send_msg() {
  local MSG="$1"

  curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
    -d "chat_id=$CHAT_ID&parse_mode=html&text=$MSG" \
    -d "reply_to_message_id=$TOPIC_ID" \
    -d disable_web_page_preview=true
}

repo sync -c --force-sync --optimized-fetch --no-tags --no-clone-bundle --prune -j$(nproc --all)

if [ $? -ne 0 ]; then
  send_msg "❌ Sync Failed!"
  exit 1
fi

send_msg "✅ Source has been fully synced!"
