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

# Device
DEVICE="$1"
BUILD_TYPE="$2"

# Vars
if [ -f "$ROM_DIR/vars.txt" ]; then
  FLAG_CI_BUILD=y
  export $(grep -vE '^\s*(#|$)' "$ROM_DIR/vars.txt")
fi

# Arg parsing
for arg in "$@"; do
  case "$arg" in
    --makeclean)
      echo -e "${BLD_BLU}Cleaning all compiled files from previous builds...${RST}"
      rm -rf "$ROM_DIR/out"
      echo -e "${BLD_BLU}Done!${RST}"
      ;;
    --installclean)
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
    --upload-gofile)
      UPLOAD_HOST="gofile"
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
push_msg() {
  [ "${FLAG_BUILD_ABORTED:-n}" = "y" ] && return 0

  local MSG="$1"

  curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
    -d "chat_id=$CHAT_ID&parse_mode=html&text=$MSG" \
    -d "reply_to_message_id=$TOPIC_ID" \
    -d disable_web_page_preview=true
}

# Check device vars
check_vars() {
  if [ -z "$DEVICE" ] || [ -z "$BUILD_TYPE" ]; then
    echo -e "${BLD_RED}WARNING: DEVICE and BUILD_TYPE must be defined!${RST}"
    echo -e "${BLD_CYA}Usage: $0 <DEVICE> <BUILD_TYPE>${RST}"
    echo -e "${BLD_CYA}Example: $0 alioth userdebug${RST}"
    exit 1
  fi

  if [[ "$BUILD_TYPE" != "eng" && "$BUILD_TYPE" != "userdebug" && "$BUILD_TYPE" != "user" ]]; then
    echo -e "${BLD_RED}WARNING: Invalid BUILD_TYPE: '$BUILD_TYPE'${RST}"
    echo -e "${BLD_CYA}Choose: eng, userdebug or user${RST}"
    exit 1
  fi

  lunching

}

# Lunch time
lunching() {
  [ "${FLAG_BUILD_ABORTED:-n}" = "y" ] && return 0

  [ "${FLAG_CI_BUILD}" = 'y' ] && local start_time=$(date +%s)
  rm -f lunch_log.txt build_log.txt

  source build/envsetup.sh
  breakfast "$DEVICE" "$BUILD_TYPE" &>lunch_log.txt

  if grep -q "dumpvars failed with" lunch_log.txt; then
    echo -e "${BLD_RED}Lunch failed!${RST}"
    if [ "${FLAG_CI_BUILD}" = 'y' ]; then
      push_msg "Lunch failed"
      curl -F chat_id="$CHAT_ID" -F reply_to_message_id="$TOPIC_ID" -F document=@"lunch_log.txt" \
        "https://api.telegram.org/bot$BOT_TOKEN/sendDocument"
    fi
  else
    if [ "${FLAG_CI_BUILD}" = 'y' ]; then
      BUILD_NUMBER=$(grep '^BUILD_ID=' lunch_log.txt | cut -d'=' -f2)
      CUSTOM_ANDROID_VERSION=$(grep '^PLATFORM_VERSION=' lunch_log.txt | cut -d'=' -f2)
      push_msg "<b>🛠 CI | PixelOS ($CUSTOM_ANDROID_VERSION)</b>%0A<b>Device:</b> <code>$DEVICE</code>%0A<b>Build type:</b> <code>$BUILD_TYPE</code>%0A<b>ID:</b> <code>$BUILD_NUMBER</code>"
    fi
    building
  fi
}

# Build time
building() {
  [ "${FLAG_INSTALLCLEAN_BUILD}" = 'y' ] && make installclean &>build_log.txt
  mka bacon -j "$JOBS" &>build_log.txt

  if [ "${FLAG_CI_BUILD}" = 'y' ]; then
    local end_time=$(date +%s)
    build_status $start_time $end_time
  else
    build_status
  fi
}

# Timer
count_build_time() {
  local start_time=$1
  local end_time=$2

  local duration=$((end_time - start_time))
  local seconds=$((duration % 60))
  local minutes=$((duration / 60 % 60))
  local hours=$((duration / 3600))

  local time_message=""
  [ $hours -gt 0 ] && time_message="${hours}h "
  [ $minutes -gt 0 ] && time_message="${time_message}${minutes}min "
  [ $seconds -gt 0 ] && time_message="${time_message}${seconds}s "

  echo "$time_message"
}

# Build status
build_status() {
  [ "${FLAG_BUILD_ABORTED:-n}" = "y" ] && return 0

  if [ "${FLAG_CI_BUILD}" = 'y' ]; then
    local start_time=$1
    local end_time=$2
    build_time=$(count_build_time $start_time $end_time)
  fi

  if grep -q "build bacon (priority: 1)" build_log.txt; then
    BUILD_PACKAGE=$(grep '^Package Complete:' build_log.txt | cut -d':' -f2)

    if [ "${FLAG_CI_BUILD}" = 'y' ]; then
      BUILD_NAME=$(basename "$BUILD_PACKAGE")
      MD5_CHECK=$(md5sum "$BUILD_PACKAGE" | awk '{print $1}')
      push_msg "Build completed successfully%0ATotal time elapsed: <b>$build_time</b>"
    fi
    uploading
  else
    push_log
  fi
}

# File upload
uploading() {
  case "$UPLOAD_HOST" in
    gofile)
      echo -e "${ORANGE}Starting upload to Gofile...${RST}"
      gofile_upload "$BUILD_PACKAGE"
      ;;
    *)
      echo -e "${BLD_BLU}No upload host defined!${RST}"
      ;;
  esac
}

# Upload to Gofile
gofile_upload() {
  local FILE_PATH="$1"
  local FILE_NAME="${FILE_PATH##*/}"

  local response
  response=$(curl -# -F "name=$FILE_NAME" -F "file=@$FILE_PATH" "https://store1.gofile.io/contents/uploadfile")

  local UPLOAD_STATUS
  UPLOAD_STATUS=$(echo "$response" | grep -Po '(?<="status":")[^"]*')

  if [ "$UPLOAD_STATUS" = 'ok' ]; then
    local URL_ID
    URL_ID=$(echo "$response" | grep -Po '(?<="downloadPage":")[^"]*')

    echo -e "${ORANGE}Upload complete!${RST}"
    if [ "${FLAG_CI_BUILD}" = 'y' ]; then
      push_msg "Uploaded to Gofile%0A1. $BUILD_NAME | <b>MD5: </b><code>$MD5_CHECK</code>%0A<b>Download:</b> $URL_ID"
    else
      echo -e "${ORANGE}Download: $URL_ID${RST}"
    fi
  else
    echo -e "${RED}Upload failed!${RST}"
    [ "${FLAG_CI_BUILD}" = 'y' ] && push_msg "Upload failed!"
  fi
}

# Build log
push_log() {
  [ "${FLAG_BUILD_ABORTED:-n}" = "y" ] && return 0

  local LOG="$ROM_DIR/out/error.log"

  echo -e "${BLD_RED}Build failed!${RST}"
  if [ "${FLAG_CI_BUILD}" = 'y' ]; then
    push_msg "Build failed"
    curl -F chat_id="$CHAT_ID" -F reply_to_message_id="$TOPIC_ID" -F document=@"$LOG" \
      "https://api.telegram.org/bot$BOT_TOKEN/sendDocument"
  else
    PAST_LOG="$(cat $LOG)"
    response=$(curl -s -d "$PAST_LOG" https://paste.crdroid.net/documents)
    KEY=$(echo "$response" | grep -Po '(?<="key":")[^"]*')
    echo -e "${BLD_RED}Log info: https://paste.crdroid.net/$KEY${RST}"
  fi
}

check_vars
