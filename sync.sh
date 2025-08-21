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

send_msg "✈️ Sync inicied!"

START_TIME=$(date +%s)

repo sync -c --force-sync --optimized-fetch --no-tags --no-clone-bundle --prune -j$(nproc --all)

if [ $? -ne 0 ]; then
  send_msg "❌ Sync Failed!"
  exit 1
fi

END_TIME=$(date +%s)

# Timer
count_sync_time() {
  local ELAPSED=$((END_TIME - START_TIME))

  local HOURS=$((ELAPSED / 3600))
  local MINUTES=$(((ELAPSED % 3600) / 60))
  local SECONDS=$((ELAPSED % 60))

  if [ $HOURS -eq 0 ]; then
    if [ $SECONDS -le 9 ]; then
      echo "${MINUTES} min"
    else
      echo "${MINUTES} min ${SECONDS} s"
    fi
  else
    if [ $SECONDS -le 9 ]; then
      echo "${HOURS} h ${MINUTES} min"
    else
      echo "${HOURS} h ${MINUTES} min ${SECONDS} s"
    fi
  fi
}

SYNC_TIME=$(count_sync_time)

send_msg "<b>✅ Source has been fully synced! </b>%0A⏱ <b>Total time elapsed: $SYNC_TIME</b>"
