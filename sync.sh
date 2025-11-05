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

if [ -z "$BOT_TOKEN" ] || ( [ -z "$CHAT_ID" ] && [ -z "$TOPIC_ID" ] ); then
  echo "❌ BOT_TOKEN and at least one of CHAT_ID or TOPIC_ID must be defined in vars.txt"
  exit 1
fi

# Identify ROM folder/org
ROM_NAME="$(basename "$ROM_DIR")"
ORG_NAME=$(grep -oP '(?<=url = https://github.com/)[^/]+(?=/)' .repo/manifests/.git/config 2>/dev/null | head -n1 || echo "$ROM_NAME")

# Identify branch
MANIFEST_BRANCH=$(git -C .repo/manifests rev-parse HEAD 2>/dev/null)
MANIFEST_BRANCH=$(git -C .repo/manifests branch -r --contains "$MANIFEST_BRANCH" 2>/dev/null | head -n1)
MANIFEST_BRANCH=$(echo "$MANIFEST_BRANCH" | sed 's#.*/##; s#.*-> ##' | xargs)
if [ -z "$MANIFEST_BRANCH" ]; then
    MANIFEST_BRANCH=$(grep -oP '(?<=<default revision=")[^"]+' .repo/manifests/default.xml 2>/dev/null)
fi

# Send TG msg
send_msg() {
  local MSG="$1"

  curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
    -d "chat_id=$CHAT_ID&parse_mode=html&text=$MSG" \
    -d "reply_to_message_id=$TOPIC_ID" \
    -d disable_web_page_preview=true
}

# Handle Ctrl+C (user interruption)
trap 'on_interrupt' SIGINT
on_interrupt() {
    echo "❌ Sync interrupted by user."
    send_msg "<b>Sync was interrupted by user (Ctrl+C).</b>"
    exit 130
}

# Start sync
send_msg "Sync of <b>$ORG_NAME</b> (<b>$MANIFEST_BRANCH</b>) started!"

START_TIME=$(date +%s)

repo sync -c --force-sync --optimized-fetch --no-tags --no-clone-bundle --prune -j$(nproc --all)
SYNC_RESULT=$?

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

if [ $SYNC_RESULT -eq 0 ]; then
  send_msg "<b>$ORG_NAME</b> was successfully synced!%0A<b>Total time elapsed:</b> $SYNC_TIME"
  echo "✅ Sync completed in $SYNC_TIME"
else
  send_msg "<b>$ORG_NAME</b> experienced sync failures.%0ACheck the log on the server."
  echo "❌ Sync failed after $SYNC_TIME"
  exit 1
fi
