#!/bin/bash
# Colors

ROM_DIR="$(pwd)"

# User vars
VARS_FILE="$ROM_DIR/vars.txt"
if [ ! -f "$VARS_FILE" ]; then
  echo "❌ File vars.txt not found."
  exit 1
fi

export $(grep -vE '^\s*(#|$)' "$ROM_DIR/vars.txt")

if [ -z "$BOT_TOKEN" ] || { [ -z "$CHAT_ID" ] && [ -z "$TOPIC_ID" ]; }; then
  echo -e "❌ BOT_TOKEN and at least one of CHAT_ID or TOPIC_ID must be defined in vars.txt"
  exit 1
fi

# Send TG msg
send_msg() {
  local MSG="$1"

  curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
    -d "chat_id=$CHAT_ID&parse_mode=html&text=$MSG" \
    -d "reply_to_message_id=$TOPIC_ID" \
    -d disable_web_page_preview=true
}

send_msg "Sync started!"

START_TIME=$(date +%s)

repo sync -c --force-sync --optimized-fetch --no-tags --no-clone-bundle --prune -j$(nproc --all)

if [ $? -ne 0 ]; then
  send_msg "Sync Failed!"
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

send_msg "<b>Source has been fully synced! </b>%0A<b>Total time elapsed: $SYNC_TIME</b>"
