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

# Guard
baiano_not_dream() {
  echo -e "${BLD_RED}Build aborted!${RST}"
  FLAG_BUILD_ABORTED=y
  exit 1
}

trap baiano_not_dream INT

if [ -f "$ROM_DIR/vars.txt" ]; then
  FLAG_CI_BUILD=y
  export $(grep -vE '^\s*(#|$)' "$ROM_DIR/vars.txt")
fi

# Device
DEVICE="$1"
BUILD_TYPE="$2"

# Out
OUT_DIR="$ROM_DIR/out/target/product/$DEVICE"

# Vars
PROJECT_NAME="PixelOS"
PROJECT_VERSION="15"
OTA_PKG="$PROJECT_NAME*$DEVICE-$PROJECT_VERSION.0-*.zip"

# Arg parsing
for arg in "$@"; do
  case "$arg" in
    --makeclean)
      echo -e "${BLD_BLU}Cleaning all compiled files from previous builds...${RST}"
      rm -rf "$ROM_DIR/out"
      echo -e "${BLD_BLU}Done!${RST}"
      ;;
    --installclean)
      echo -e "${BLD_BLU}Cleaning compiled files from previous builds...${RST}"
      FLAG_INSTALLCLEAN_BUILD=y
      ;;
    --full-jobs)
      ALL_PROCS=$(nproc)
      FLAG_FULL_JOBS=y
      ;;
    --j*)
      CUSTOM_JOBS="${arg#--j}"
      FLAG_CUSTOM_JOBS=y
      ;;
    --upload-gdrive)
      UPLOAD_HOST="gdrive"
      ;;
    --upload-gofile)
      UPLOAD_HOST="gofile"
      ;;
    --upload-pixeldrain)
      UPLOAD_HOST="pixeldrain"
      ;;
  esac
done

# Jobs
if [ "${FLAG_FULL_JOBS}" = 'y' ]; then
  JOBS="$ALL_PROCS"
elif [ "${FLAG_CUSTOM_JOBS}" = 'y' ]; then
  JOBS="$CUSTOM_JOBS"
else
  echo -e "${BLD_BLU}WARNING: No number of jobs defined! Using default value: 16.${RST}"
  JOBS=16
fi

# Send Telegram message
send_msg() {
  [ "${FLAG_BUILD_ABORTED:-n}" = "y" ] && return 0

  local MSG="$1"

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

# Check device vars
check_vars() {
  if [ -z "$DEVICE" ] || [ -z "$BUILD_TYPE" ]; then
    echo -e "${BLD_RED}ERROR: DEVICE and BUILD_TYPE must be defined!${RST}"
    echo -e "${BLD_RED}Usage: $0 <DEVICE> <BUILD_TYPE>${RST}"
    echo -e "${BLD_RED}Example: $0 alioth userdebug${RST}"
    exit 1
  fi

  if [[ "$BUILD_TYPE" != "eng" && "$BUILD_TYPE" != "userdebug" && "$BUILD_TYPE" != "user" ]]; then
    echo -e "${BLD_RED}ERROR: Invalid BUILD_TYPE: '$BUILD_TYPE'${RST}"
    echo -e "${BLD_RED}Choose: eng, userdebug or user${RST}"
    exit 1
  fi

  lunching

}

# Lunch time
lunching() {
  [ "${FLAG_BUILD_ABORTED:-n}" = "y" ] && return 0

  [ "${FLAG_CI_BUILD}" = 'y' ] && local START_TIME=$(date +%s)
  rm -f lunch_log.txt

  source build/envsetup.sh
  breakfast "$DEVICE" "$BUILD_TYPE" &>lunch_log.txt

  if grep -q "dumpvars failed with" lunch_log.txt; then
    if [ "${FLAG_CI_BUILD}" = 'y' ]; then
      send_msg "<b>❌ Lunch failed!</b>"
      send_file "lunch_log.txt"
    fi
    echo -e "${BLD_RED}ERROR: Lunch failed!${RST}"
  else
    if [ "${FLAG_CI_BUILD}" = 'y' ]; then
      BUILD_NUMBER=$(grep '^BUILD_ID=' lunch_log.txt | cut -d'=' -f2)
      send_msg "<b>🛠 CI | $PROJECT_NAME $PROJECT_VERSION</b>%0A<b>Device:</b> <code>$DEVICE</code>%0A<b>Type:</b> <code>$BUILD_TYPE</code>%0A<b>ID:</b> <code>$BUILD_NUMBER</code>"
    fi
    building
  fi
}

# Build time
building() {
  [ "${FLAG_INSTALLCLEAN_BUILD}" = 'y' ] && make installclean
  mka bacon -j "$JOBS"

  if [ "${FLAG_CI_BUILD}" = 'y' ]; then
    local END_TIME=$(date +%s)
    build_status $START_TIME $END_TIME
  else
    build_status
  fi
}

# Timer
count_build_time() {
  local START_TIME=$1
  local END_TIME=$2

  local DURATION=$((END_TIME - START_TIME))
  local SECONDS=$((DURATION % 60))
  local MINUTES=$((DURATION / 60 % 60))
  local HOURS=$((DURATION / 3600))

  local TIME_MSG=""
  [ $HOURS -gt 0 ] && TIME_MSG="${HOURS} h "
  [ $MINUTES -gt 0 ] && TIME_MSG="${TIME_MSG}${MINUTES} min "
  [ $SECONDS -gt 0 ] && TIME_MSG="${TIME_MSG}${SECONDS} s "

  echo "$TIME_MSG"
}

# Build status
build_status() {
  [ "${FLAG_BUILD_ABORTED:-n}" = "y" ] && return 0

  if [ "${FLAG_CI_BUILD}" = 'y' ]; then
    local START_TIME=$1
    local END_TIME=$2
    BUILD_TIME=$(count_build_time $START_TIME $END_TIME)
  fi

  BUILD_PKG="$(find "$OUT_DIR" -name "$OTA_PKG" -print -quit)"

  if [ -n "$BUILD_PKG" ]; then
    if [ "${FLAG_CI_BUILD}" = 'y' ]; then
      BUILD_NAME=$(basename "$BUILD_PKG")
      OTA_PKG_SHA256=$(sha256sum "$BUILD_PKG" | awk '{print $1}')
      send_msg "<b>✅ Build completed</b>%0A⏱ <b>$BUILD_TIME</b>"
    fi
    uploading
  else
    push_log
  fi
}

# File upload
uploading() {
  case "$UPLOAD_HOST" in
    gdrive)
      echo -e "${GRN}Starting upload to Google Drive...${RST}"
      UPLOAD_HOST_NAME="Google Drive"
      rclone_upload "$BUILD_PKG" "gdrive"
      ;;
    gofile)
      echo -e "${ORANGE}Starting upload to Gofile...${RST}"
      UPLOAD_HOST_NAME="Gofile"
      gofile_upload "$BUILD_PKG"
      ;;
    pixeldrain)
      echo -e "${LIGHT_GREEN}Starting upload to PixelDrain...${RST}"
      UPLOAD_HOST_NAME="Pixel Drain"
      pixeldrain_upload "$BUILD_PKG"
      ;;
    *)
      [ "${FLAG_CI_BUILD}" = 'y' ] && send_msg "<b>✅ Build completed</b>%0A⏱ <b>$BUILD_TIME</b>"
      echo -e "${BLD_BLU}WARNING: No upload host defined!${RST}"
      ;;
  esac
}

# Upload to Gofile
gofile_upload() {
  local FILE_PATH="$1"
  local FILE_NAME="${FILE_PATH##*/}"

  local RESPONSE
  RESPONSE=$(curl -# -F "name=$FILE_NAME" -F "file=@$FILE_PATH" "https://store1.gofile.io/contents/uploadfile")

  local UPLOAD_STATUS
  UPLOAD_STATUS=$(echo "$RESPONSE" | grep -Po '(?<="status":")[^"]*')

  if [ "$UPLOAD_STATUS" = 'ok' ]; then
    local URL_ID
    URL_ID=$(echo "$RESPONSE" | grep -Po '(?<="downloadPage":")[^"]*')

    echo -e "${ORANGE}Upload complete!${RST}"
    if [ "${FLAG_CI_BUILD}" = 'y' ]; then
      send_msg "🚀 <code>$BUILD_NAME</code>%0A🔐 <b>SHA256: </b><code>$OTA_PKG_SHA256</code>%0A🔗 <b>Download:</b> <a href=\"$URL_ID\">$UPLOAD_HOST_NAME</a>"
    else
      echo -e "${ORANGE}Download: $URL_ID${RST}"
    fi
  else
    [ "${FLAG_CI_BUILD}" = 'y' ] && send_msg "❌ Upload failed!"
    echo -e "${BLD_RED}ERROR: Upload failed!${RST}"
  fi
}

# Upload to PixelDrain
pixeldrain_upload() {
  local FILE_PATH="$1"
  local FILE_NAME="${FILE_PATH##*/}"

  if [ -z "$PIXELDRAIN_API_TOKEN" ]; then
    [ "${FLAG_CI_BUILD}" = 'y' ] && send_msg "<b>❌ Upload failed: <i>PIXELDRAIN_API_TOKEN</i> not found!</b>"
    echo -e "${BLD_RED}ERROR: PIXELDRAIN_API_TOKEN not found!${RST}"
    return 1
  fi

  RESPONSE=$(curl -T "$FILE_PATH" -u :$PIXELDRAIN_API_TOKEN https://pixeldrain.com/api/file/)

  PD_UPLOAD_ID=$(echo "$RESPONSE" | grep -Po '(?<="id":")[^\"]*')
  if [ -n "$PD_UPLOAD_ID" ]; then
    URL_ID="https://pixeldrain.com/u/$PD_UPLOAD_ID"
    if [ "${FLAG_CI_BUILD}" = 'y' ]; then
      send_msg "🚀 <code>$BUILD_NAME</code>%0A🔐 <b>SHA256: </b><code>$OTA_PKG_SHA256</code>%0A🔗 <b>Download:</b> <a href=\"$URL_ID\">$UPLOAD_HOST_NAME</a>"
      echo -e "${LIGHT_GREEN}Upload complete!${RST}"
    else
      echo -e "${LIGHT_GREEN}Download: $URL_ID${RST}"
    fi
  else
    [ "${FLAG_CI_BUILD}" = 'y' ] && send_msg "❌ Upload failed!"
    echo -e "${BLD_RED}ERROR: Upload failed!${RST}"
    return 1
  fi
}

rclone_upload() {
  local FILE_PATH="$1"
  local HOST="$2"

  RCLONE_BIN=$(command -v rclone)
  RCLONE_CONF="$HOME/.config/rclone/rclone.conf"

  if [[ -z "$RCLONE_BIN" ]]; then
    [ "${FLAG_CI_BUILD}" = 'y' ] && send_msg "❌ Upload failed: <i>rclone</i> is not installed!"
    echo "${BLD_RED}ERROR: rclone is not installed!${RST}"
    exit 1
  elif [[ ! -f "$RCLONE_CONF" ]]; then
    [ "${FLAG_CI_BUILD}" = 'y' ] && send_msg "❌ Upload failed: <i>rclone.config</i> not found!!"
    echo "${BLD_RED}ERROR: rclone.config not found!${RST}"
    exit 1
  fi

  if [[ -z "${UPLOAD_FOLDER:-}" ]]; then
    UPLOAD_FOLDER=android
  fi

  rclone copy $FILE_PATH $HOST:$UPLOAD_FOLDER

  [ "${FLAG_CI_BUILD}" = 'y' ] && send_msg "🚀 <code>$BUILD_NAME</code>%0A🔐 SHA256: <code>$OTA_PKG_SHA256</code>"
  echo -e "${GRN}Upload complete!${RST}"
}

# Build log
push_log() {
  [ "${FLAG_BUILD_ABORTED:-n}" = "y" ] && return 0

  local LOG="$ROM_DIR/out/error.log"

  if [ "${FLAG_CI_BUILD}" = 'y' ]; then
    send_msg "❌ Build failed"
    send_file "$LOG"
  else
    echo -e "${BLD_RED}ERROR: Build failed!${RST}"
    PAST_LOG="$(cat $LOG)"
    RESPONSE=$(curl -s -d "$PAST_LOG" https://paste.crdroid.net/documents)
    KEY=$(echo "$RESPONSE" | grep -Po '(?<="key":")[^"]*')
    echo -e "${BLD_RED}Log info: https://paste.crdroid.net/$KEY${RST}"
  fi
}

check_vars
