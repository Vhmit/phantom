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

# Defaults
BUILD_TYPE="user"
JOBS="$(nproc)"
UPLOAD_HOST="gofile"

# User vars
if [[ -z "$ROM_DIR/vars.txt" ]]; then
  echo -e "${BLD_RED}ERROR: The variables file [vars.txt] was not found!${RST}"
  exit 1
fi

export $(grep -vE '^\s*(#|$)' "$ROM_DIR/vars.txt")

# Guard
phantom_not_dream() {
  echo -e "${BLD_RED}Build aborted!${RST}"
  FLAG_BUILD_ABORTED=y
  exit 1
}

trap phantom_not_dream INT

# Out
OUT_DIR="$ROM_DIR/out/target/product/$DEVICE"

# Output usage help
showHelpAndExit() {
  echo -e "${CLR_BLD_BLU}Usage: $0 <device> [options]${CLR_RST}"
  echo -e ""
  echo -e "${CLR_BLD_BLU}Options:${CLR_RST}"
  echo -e "${CLR_BLD_BLU}  -h, --help                Display this help message${CLR_RST}"
  echo -e "${CLR_BLD_BLU}  -t, --build-type TYPE     Type of build: eng, user, userdebug (default: user)${CLR_RST}"
  echo -e "${CLR_BLD_BLU}  -c, --clean               Wipe the tree before building${CLR_RST}"
  echo -e "${CLR_BLD_BLU}  -i, --installclean        Dirty build - Use 'installclean'${CLR_RST}"
  echo -e "${CLR_BLD_BLU}  -j, --jobs N              Number of parallel jobs (default: all threads)${CLR_RST}"
  echo -e "${CLR_BLD_BLU}  -u, --upload HOST         Upload host:gofile, pixeldrain${CLR_RST}"
  exit 1
}

# Setup getopt
LONG_OPTS="help,build-type:,clean,installclean,jobs:,upload:"
GETOPT_CMD=$(getopt -o hcij:t:u: --long "$LONG_OPTS" \
  -n $(basename $0) -- "$@") ||
  {
    echo -e "${CLR_BLD_RED}\nError: Getopt failed. Extra args\n${CLR_RST}"
    showHelpAndExit
    exit 1
  }

eval set -- "$GETOPT_CMD"

while true; do
  case "$1" in
    -h|--help|h|help) showHelpAndExit;;
    -c|--clean|c|clean) FLAG_CLEAN_BUILD=y;;
    -i|--installclean|i|installclean) FLAG_INSTALLCLEAN_BUILD=y;;
    -j|--jobs|j|jobs) JOBS="$2"; shift;;
    -t|--build-type|t|build-type) BUILD_TYPE="$2"; shift;;
    -u|--upload|u|upload) UPLOAD_HOST="$2"; shift;;
    --) shift; break;;
  esac
  shift
done

# Check if mandatory vars have been defined
# Device and build type
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

# Bot token and chat ID
if [ -z "$BOT_TOKEN" ] || [ -z "$CHAT_ID" ]; then
  echo -e "${BLD_RED}ERROR: BOT_TOKEN and CHAT_ID must be defined!${RST}"
  exit 1
fi

# Send TG msg
send_msg() {
  [ "${FLAG_BUILD_ABORTED:-n}" = "y" ] && return 0

  local MSG="$1"

  curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
    -d "chat_id=$CHAT_ID&parse_mode=html&text=$MSG" \
    -d "reply_to_message_id=$TOPIC_ID" \
    -d disable_web_page_preview=true
}

clean_house() {
  rm -f lunch_log.txt

  if [ "${FLAG_CLEAN_BUILD}" = 'y' ]; then
    echo -e "${BLD_BLU}Cleaning all compiled files from previous builds...${RST}"

    source build/envsetup.sh
    breakfast "$DEVICE" "$BUILD_TYPE"
    make clean
  elif [ "${FLAG_INSTALLCLEAN_BUILD}" = 'y' ]; then
    echo -e "${BLD_BLU}Cleaning compiled files from previous builds...${RST}"
    rm -f $OUT_DIR/PixelOS_$DEVICE-*

    source build/envsetup.sh
    breakfast "$DEVICE" "$BUILD_TYPE"
    make installclean
  fi
}

check_sha256() {
  local FILE="$1"

  if [[ ! -f "$FILE" ]]; then
    echo "ERROR: '$FILE' not found!" >&2
    return 1
  fi

  sha256sum "$FILE" | awk '{print $1}'
}

# Send TG file
send_file() {
  [ "${FLAG_BUILD_ABORTED:-n}" = "y" ] && return 0

  local FILE="$1"

  curl "https://api.telegram.org/bot$BOT_TOKEN/sendDocument" \
    -F chat_id="$CHAT_ID" \
    -F reply_to_message_id="$TOPIC_ID" \
    -F document=@"$FILE"
}

# Lunch time
lunching() {
  [ "${FLAG_BUILD_ABORTED:-n}" = "y" ] && return 0

  START_TIME=$(date +%s)

  source build/envsetup.sh
  breakfast "$DEVICE" "$BUILD_TYPE" &>lunch_log.txt

  if grep -q "dumpvars failed with" lunch_log.txt; then
    send_msg "<b>❌ Lunch failed!</b>"
    send_file lunch_log.txt
  else
    # Vars
    BUILD_NUMBER="$(get_build_var BUILD_ID)"
    PROJECT_VERSION="$(get_build_var PLATFORM_VERSION)"

    send_msg "<b>🛠 CI | PixelOS $PROJECT_VERSION</b>%0A<b>Device:</b> <code>$DEVICE</code>%0A<b>Type:</b> <code>$BUILD_TYPE</code>%0A<b>ID:</b> <code>$BUILD_NUMBER</code>"
    building
  fi
}

# Build time
building() {
  mka bacon -j "$JOBS"

  END_TIME=$(date +%s)
  build_status
}

# Timer
count_build_time() {
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

# Build status
build_status() {
  [ "${FLAG_BUILD_ABORTED:-n}" = "y" ] && return 0

  BUILD_TIME=$(count_build_time)

  BUILD_PACKAGE="$(find "$OUT_DIR" -name "PixelOS_$DEVICE-$PROJECT_VERSION.0-*.zip" -print -quit)"

  if [ -n "$BUILD_PACKAGE" ]; then
    BUILD_NAME=$(basename "$BUILD_PACKAGE")
    BUILD_PACKAGE_SHA256=$(check_sha256 "$BUILD_PACKAGE")

    send_msg "<b>✅ Build completed</b>%0A⏱ <b>$BUILD_TIME</b>"
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
      UPLOAD_HOST_NAME="Gofile"
      gofile_upload "$BUILD_PACKAGE"
      ;;
    pixeldrain)
      echo -e "${LIGHT_GREEN}Starting upload to PixelDrain...${RST}"
      UPLOAD_HOST_NAME="Pixel Drain"
      pixeldrain_upload "$BUILD_PACKAGE"
      ;;
    *)
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
    send_msg "🚀 <code>$BUILD_NAME</code>%0A🔐 <b>SHA256: </b><code>$BUILD_PACKAGE_SHA256</code>%0A🔗 <b>Download:</b> <a href=\"$URL_ID\">$UPLOAD_HOST_NAME</a>"
  else
    send_msg "❌ Upload failed!"
    echo -e "${BLD_RED}ERROR: Upload failed!${RST}"
  fi
}

# Upload to PixelDrain
pixeldrain_upload() {
  local FILE_PATH="$1"
  local FILE_NAME="${FILE_PATH##*/}"

  if [ -z "$PIXELDRAIN_API_TOKEN" ]; then
    send_msg "<b>❌ Upload failed: <i>PIXELDRAIN_API_TOKEN</i> not found!</b>"
    echo -e "${BLD_RED}ERROR: PIXELDRAIN_API_TOKEN not found!${RST}"
    return 1
  fi

  RESPONSE=$(curl -T "$FILE_PATH" -u :$PIXELDRAIN_API_TOKEN https://pixeldrain.com/api/file/)

  PD_UPLOAD_ID=$(echo "$RESPONSE" | grep -Po '(?<="id":")[^\"]*')
  if [ -n "$PD_UPLOAD_ID" ]; then
    URL_ID="https://pixeldrain.com/u/$PD_UPLOAD_ID"
    send_msg "🚀 <code>$BUILD_NAME</code>%0A🔐 <b>SHA256: </b><code>$BUILD_PACKAGE_SHA256</code>%0A🔗 <b>Download:</b> <a href=\"$URL_ID\">$UPLOAD_HOST_NAME</a>"
    echo -e "${LIGHT_GREEN}Upload complete!${RST}"
  else
    send_msg "❌ Upload failed!"
    echo -e "${BLD_RED}ERROR: Upload failed!${RST}"
    return 1
  fi
}

# Build log
push_log() {
  [ "${FLAG_BUILD_ABORTED:-n}" = "y" ] && return 0

  local LOG="$ROM_DIR/out/error.log"

  send_msg "❌ Build failed"
  send_file "$LOG"
}

clean_house
lunching
