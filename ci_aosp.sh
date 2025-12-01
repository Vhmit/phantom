#!/bin/bash
# Colors
RST=$(tput sgr0)
RED=$RST$(tput setaf 1)
GRN=$RST$(tput setaf 2)
BLU=$RST$(tput setaf 4)
CYA=$RST$(tput setaf 6)
LIGHT_GREEN=$RST$(tput setaf 120)
ORANGE=$RST$(tput setaf 214)
BLD=$(tput bold)
BLD_RED=$RST$BLD$(tput setaf 1)
BLD_GRN=$RST$BLD$(tput setaf 2)
BLD_BLU=$RST$BLD$(tput setaf 4)
BLD_CYA=$RST$BLD$(tput setaf 6)

ROM_DIR="$(pwd)"

# Device
DEVICE="$1"

# Out
OUT_DIR="$ROM_DIR/out/target/product/$DEVICE"

# Defaults
BUILD_TYPE="userdebug"
JOBS=$(nproc --all)
UPLOAD_HOST="gofile"
VARS_FILE="$ROM_DIR/vars.txt"

# Dependencies
check_deps() {
    local deps=("repo" "jq" "curl" "sha256sum")
    for cmd in "${deps[@]}"; do
        command -v $cmd >/dev/null 2>&1 || { echo -e "${BLD_RED}❌ '$cmd' not found. Install it first.${RST}"; exit 1; }
    done
}

check_deps

# User vars
if [ ! -f "$VARS_FILE" ]; then
  echo -e "${BLD_RED}ERROR: The variables file [vars.txt] was not found!${RST}"
  exit 1
fi
# Export safely
set -a
source "$VARS_FILE"
set +a

# Verify repository has been initialized
if [ ! -d ".repo/manifests" ]; then
    echo "❌ Repo not initialized. Please run repo init first."
    exit 1
fi

# Guard and interrupt
phantom_not_dream() {
    echo -e "${BLD_RED}❌ Sync interrupted by user.${RST}"
    if [ "${FLAG_SYNC_ONLY:-n}" = "y" ]; then
        on_interrupt_sync
    fi
    exit 1
}

on_interrupt_sync() {
    send_msg "<b>Sync was interrupted by user (Ctrl+C).</b>"
    exit 130
}

trap_build_ctrlc() {
    echo -e "${BLD_RED}❌ Build aborted!${RST}"
    FLAG_BUILD_ABORTED=y
    send_msg "<b>Build aborted!</b>"
    exit 130
}

# Set trap for build early, before clean/meal/lunch/build
trap trap_build_ctrlc INT

# Send TG msg/file
send_msg() {
  local MSG="$1"
  if [[ "$MSG" == *"Build aborted!"* ]]; then
      curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
           -d "chat_id=$CHAT_ID&parse_mode=html&text=$MSG" \
           -d "reply_to_message_id=$TOPIC_ID" \
           -d disable_web_page_preview=true
      return
  fi
  [ "${FLAG_BUILD_ABORTED:-n}" = "y" ] && return 0
  curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
       -d "chat_id=$CHAT_ID&parse_mode=html&text=$MSG" \
       -d "reply_to_message_id=$TOPIC_ID" \
       -d disable_web_page_preview=true
}

send_file() {
  [ "${FLAG_BUILD_ABORTED:-n}" = "y" ] && return 0
  local FILE="$1"
  curl "https://api.telegram.org/bot$BOT_TOKEN/sendDocument" \
       -F chat_id="$CHAT_ID" \
       -F reply_to_message_id="$TOPIC_ID" \
       -F document=@"$FILE"
}

# Identify ROM/branch
ROM_NAME="$(basename "$ROM_DIR")"
ORG_NAME=$(grep -oP '(?<=url = https://github.com/)[^/]+(?=/)' .repo/manifests/.git/config 2>/dev/null | head -n1 || echo "$ROM_NAME")
MANIFEST_BRANCH=$(git -C .repo/manifests rev-parse HEAD 2>/dev/null)
MANIFEST_BRANCH=$(git -C .repo/manifests branch -r --contains "$MANIFEST_BRANCH" 2>/dev/null | head -n1)
MANIFEST_BRANCH=$(echo "$MANIFEST_BRANCH" | sed 's#.*/##; s#.*-> ##' | xargs)
if [ -z "$MANIFEST_BRANCH" ]; then
    MANIFEST_BRANCH=$(grep -oP '(?<=<default revision=")[^"]+' .repo/manifests/default.xml 2>/dev/null)
fi

# Time counter
count_time() {
    local START=$1
    local END=$2
    local ELAPSED=$((END-START))
    local H=$((ELAPSED/3600))
    local M=$(((ELAPSED%3600)/60))
    local S=$((ELAPSED%60))
    if [ $H -eq 0 ]; then
        if [ $S -le 9 ]; then
            echo "${M} min"
        else
            echo "${M} min ${S} s"
        fi
    else
        if [ $S -le 9 ]; then
            echo "${H} h ${M} min"
        else
            echo "${H} h ${M} min ${S} s"
        fi
    fi
}

# Repo sync
run_sync() {
  FLAG_SYNC_ONLY=y
  trap phantom_not_dream INT

  send_msg "Sync of <b>$ORG_NAME</b> (<b>$MANIFEST_BRANCH</b>) started!"
  echo -e "${BLD_CYA}Starting repo sync for $ORG_NAME ($MANIFEST_BRANCH)...${RST}"

  START_TIME=$(date +%s)
  repo sync -c -j"$JOBS" --force-sync --no-clone-bundle --no-tags
  SYNC_RESULT=$?
  END_TIME=$(date +%s)
  SYNC_TIME=$(count_time $START_TIME $END_TIME)

  if [ $SYNC_RESULT -eq 0 ]; then
    send_msg "<b>$ORG_NAME</b> was successfully synced!%0A<b>Total time elapsed:</b> $SYNC_TIME"
    echo -e "${BLD_GRN}✅ Sync completed in $SYNC_TIME${RST}"
  else
    send_msg "<b>$ORG_NAME</b> sync failed. Check logs."
    echo -e "${BLD_RED}❌ Sync failed after $SYNC_TIME${RST}"
    exit 1
  fi
}

# Output usage help
showHelpAndExit() {
  echo -e "${BLD_BLU}Usage: $0 <device> [options]${RST}"
  echo -e "Options:"
  echo -e "  -h, --help           Display help"
  echo -e "  -s, --sync           Only run repo sync"
  echo -e "  -t, --build-type     eng/user/userdebug (default: userdebug)"
  echo -e "  -c, --clean          Full clean"
  echo -e "  -i, --installclean   Installclean"
  echo -e "  -j, --jobs N         Number of jobs (default: all)"
  echo -e "  -u, --upload HOST    Upload host: gofile/pdrain (default: gofile)"
  exit 1
}

LONG_OPTS="help,sync,build-type:,clean,installclean,jobs:,upload:"
GETOPT_CMD=$(getopt -o hsct:iJ:j:u: --long "$LONG_OPTS" -n $(basename $0) -- "$@") || { echo -e "${BLD_RED}Getopt failed${RST}"; showHelpAndExit; }
eval set -- "$GETOPT_CMD"

while true; do
  case "$1" in
    -h|--help) showHelpAndExit;;
    -s|--sync) FLAG_SYNC_ONLY=y;;
    -c|--clean) FLAG_CLEAN_BUILD=y;;
    -i|--installclean) FLAG_INSTALLCLEAN_BUILD=y;;
    -j|--jobs) JOBS="$2"; shift;;
    -t|--build-type) BUILD_TYPE="$2"; shift;;
    -u|--upload) UPLOAD_HOST="$2"; shift;;
    --) shift; break;;
  esac
  shift
done

# Run sync only if flag
if [ "${FLAG_SYNC_ONLY:-n}" = "y" ]; then
  run_sync
  exit 0
fi

# Check if mandatory vars have been defined
# Device and build type
if [ -z "$DEVICE" ] || [ -z "$BUILD_TYPE" ]; then
  echo -e "${BLD_RED}ERROR: DEVICE and BUILD_TYPE must be defined!${RST}"
  echo -e "${BLD_RED}Usage: $0 <DEVICE> <BUILD_TYPE>${RST}"
  echo -e "${BLD_RED}Example: $0 jeter userdebug${RST}"
  exit 1
fi

if [[ "$BUILD_TYPE" != "eng" && "$BUILD_TYPE" != "userdebug" && "$BUILD_TYPE" != "user" ]]; then
  echo -e "${BLD_RED}ERROR: Invalid BUILD_TYPE: '$BUILD_TYPE'${RST}"
  echo -e "${BLD_RED}Choose: eng, userdebug or user${RST}"
  exit 1
fi

# Bot token and chat/topic ID
if [ -z "$BOT_TOKEN" ] || [ -z "$CHAT_ID" ]; then
  echo -e "${BLD_RED}ERROR: BOT_TOKEN and CHAT/TOPIC_ID must be defined!${RST}"
  exit 1
fi

# Clean build
clean_house() {
  rm -f lunch_log.txt
  source build/envsetup.sh
  breakfast "$DEVICE" "$BUILD_TYPE"

  # Flag status
  CLEAN_STATUS=""

  if [ "${FLAG_CLEAN_BUILD}" = 'y' ]; then
    echo -e "${BLD_BLU}Full clean...${RST}"
    make clean
    CLEAN_STATUS="(fullclean)"
  elif [ "${FLAG_INSTALLCLEAN_BUILD}" = 'y' ]; then
    echo -e "${BLD_BLU}Installclean...${RST}"
    make installclean
    CLEAN_STATUS="(installclean)"
  fi
}

# SHA256
check_sha256() {
  local FILE="$1"
  [[ ! -f "$FILE" ]] && { echo "ERROR: '$FILE' not found!"; return 1; }
  sha256sum "$FILE" | awk '{print $1}'
}

# Lunch and build time
lunching() {
  [ "${FLAG_BUILD_ABORTED:-n}" = "y" ] && return 0
  START_TIME=$(date +%s)
  source build/envsetup.sh
  breakfast "$DEVICE" "$BUILD_TYPE" &>lunch_log.txt

  if grep -q "dumpvars failed with" lunch_log.txt; then
    send_msg "<b>Lunch failed!</b>"
    send_file lunch_log.txt
    exit 1
  else
    BUILD_NUMBER="$(get_build_var BUILD_ID)"
    MSG="<b>🛠 CI | $ORG_NAME</b>%0A"
        [ -n "$CLEAN_STATUS" ] && MSG+="<b>status:</b> <code>$CLEAN_STATUS</code>%0A"
        MSG+="<b>branch:</b> <code>$MANIFEST_BRANCH</code>%0A<b>Device:</b> <code>$DEVICE</code>%0A<b>Build type:</b> <code>$BUILD_TYPE</code>%0A<b>ID:</b> <code>$BUILD_NUMBER</code>"
        send_msg "$MSG"
    building
  fi
}

building() {
  make bacon -j"$JOBS"
  END_TIME=$(date +%s)
  build_status
}

build_status() {
  [ "${FLAG_BUILD_ABORTED:-n}" = "y" ] && return 0
  BUILD_TIME=$(count_time $START_TIME $END_TIME)
  BUILD_PACKAGE=$(ls -t "$OUT_DIR"/*.zip 2>/dev/null | head -n1)

  if [ -n "$BUILD_PACKAGE" ]; then
    BUILD_NAME=$(basename "$BUILD_PACKAGE")
    BUILD_PACKAGE_SHA256=$(check_sha256 "$BUILD_PACKAGE")
    send_msg "<b>Build completed successfully!</b>%0A<b>Total time:</b> $BUILD_TIME"
    uploading
  else
    push_log
  fi
}

# File upload
uploading() {
  case "$UPLOAD_HOST" in
    gofile)
      echo -e "${ORANGE}Uploading to Gofile...${RST}"
      gofile_upload "$BUILD_PACKAGE"
      ;;
    pdrain)
      echo -e "${LIGHT_GREEN}Uploading to PixelDrain...${RST}"
      pixeldrain_upload "$BUILD_PACKAGE"
      ;;
    *)
      echo -e "${BLD_BLU}No upload host defined.${RST}"
      ;;
  esac
}

gofile_upload() {
  local FILE="$1"
  local RESPONSE=$(curl -s -F "name=$(basename $FILE)" -F "file=@$FILE" "https://store1.gofile.io/contents/uploadfile")
  local STATUS=$(echo "$RESPONSE" | jq -r '.status')
  if [ "$STATUS" = "ok" ]; then
    local URL=$(echo "$RESPONSE" | jq -r '.data.downloadPage')
    send_msg "<b>Build:</b> <a href=\"$URL\">$BUILD_NAME</a>%0A<b>SHA256:</b> <code>$BUILD_PACKAGE_SHA256</code>"
  else
    send_msg "❌ Gofile upload failed!"
  fi
}

pixeldrain_upload() {
  local FILE="$1"
  [ -z "$PIXELDRAIN_API_TOKEN" ] && { send_msg "❌ PIXELDRAIN_API_TOKEN missing!"; return 1; }
  local RESPONSE=$(curl -s -T "$FILE" -u :$PIXELDRAIN_API_TOKEN https://pixeldrain.com/api/file/)
  local ID=$(echo "$RESPONSE" | jq -r '.id // empty')
  if [ -n "$ID" ]; then
    local URL="https://pixeldrain.com/u/$ID"
    send_msg "<b>Build:</b> <a href=\"$URL\">$BUILD_NAME</a>%0A<b>SHA256:</b> <code>$BUILD_PACKAGE_SHA256</code>"
  else
    send_msg "❌ PixelDrain upload failed!"
  fi
}

# Logs
katbin_upload() {
  local FILE="$1"
  [ ! -f "$FILE" ] && return 1
  local RESPONSE=$(curl -sL 'https://katb.in/api/paste' --json "$(jq -n --arg content "$(cat "$FILE")" '{"paste":{"content":$content}}')")
  local KEY=$(echo "$RESPONSE" | jq -r '.id // empty')
  [ -n "$KEY" ] && echo "https://katb.in/$KEY" || return 1
}

push_log() {
  [ "${FLAG_BUILD_ABORTED:-n}" = "y" ] && return 0
  local LOG="$ROM_DIR/out/error.log"
  [ ! -f "$LOG" ] && send_msg "❌ Log file not found!" && return 1
  local TIMESTAMP=$(TZ="America/Bahia" date +"%Y%m%d_%H%M%S")
  local OUTFILE="log_${TIMESTAMP}.txt"
  cp "$LOG" "$OUTFILE"

  send_msg "❌ Build failed!"

  if curl -s --max-time 5 -o /dev/null -w "%{http_code}" https://katb.in | grep -q '^2'; then
    URL=$(katbin_upload "$OUTFILE")
    if [[ "$URL" == https://katb.in/* ]]; then
      send_msg "Log available at: $URL"
      echo "✅ Log sent to Katbin"
    else
      send_file "$OUTFILE"
    fi
  else
    send_file "$OUTFILE"
  fi
  rm -f "$OUTFILE"
}

clean_house
lunching
