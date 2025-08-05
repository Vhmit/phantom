#!/bin/bash
# Colors
if [[ -t 1 ]] && [[ -n "$TERM" ]]; then
  RST=$(tput sgr0)
  RED=$(tput setaf 1)
  GRN=$(tput setaf 2)
  BLU=$(tput setaf 4)
  ORANGE=$(tput setaf 3)
  BLD=$(tput bold)
else
  RST=""; RED=""; GRN=""; BLU=""; ORANGE=""; BLD=""
fi

ROOT_DIR="$(pwd)"

# Device
DEVICE="$1"

# Defaults
JOBS="$(nproc)"
TOOLCHAIN="AOSP"
UPLOAD_HOST="telegram"

# User vars
VARS_FILE="$ROOT_DIR/vars.txt"
if [[ ! -f "$VARS_FILE" ]]; then
  echo -e "${RED}${BLD}ERROR:${RST} vars.txt not found in $ROOT_DIR!"
  exit 1
fi

while IFS='=' read -r key value; do
  [[ "$key" =~ ^#.*$ || -z "$key" ]] && continue
  export "$key"="$value"
done <"$VARS_FILE"

# Date
TM=$(date '+%Y%m%d-%H%M')

# Check if mandatory vars have been defined
# Bot token and chat ID
if [ -z "$BOT_TOKEN" ] || [ -z "$CHAT_ID" ]; then
  echo -e "${RED}${BLD}ERROR: BOT_TOKEN and CHAT_ID must be defined!${RST}"
  exit 1
fi

# latest commit
COMMIT_HEAD="$(git rev-parse --short HEAD)"

# Output usage help
showHelpAndExit() {
  echo -e "${BLU}${BLD}Usage: $0 <device> [options]${RST}"
  echo -e ""
  echo -e "${BLU}${BLD}Options:${RST}"
  echo -e "${BLU}${BLD}  -h, --help             Display this help message${RST}"
  echo -e "${BLU}${BLD}  -b, --beta             Beta release :)${RST}"
  echo -e "${BLU}${BLD}  -c, --toolchain NAME   Toolchain: clang (AOSP), zyc, neutron${RST}"
  echo -e "${BLU}${BLD}  -j, --jobs N           Number of parallel jobs (default: all threads)${RST}"
  echo -e "${BLU}${BLD}  -u, --upload HOST      Upload host: telegram, gofile, pixeldrain${RST}"
  exit 1
}

# Parse args
TEMP=$(getopt -o hbc:j:u: --long help,beta,jobs:,toolchain:,upload: -n "$0" -- "$@")
if [ $? -ne 0 ]; then showHelpAndExit; fi
eval set -- "$TEMP"
while true; do
  case "$1" in
    -h|--help) showHelpAndExit;;
    -b|--beta) BUILD_TYPE="BETA"; shift;;
    -c|--toolchain) TOOLCHAIN="$2"; shift 2;;
    -j|--jobs) JOBS="$2"; shift 2;;
    -u|--upload) UPLOAD_HOST="$2"; shift 2;;
    --) shift; break;;
  esac
done

# Send TG msg
send_msg() {
  local MSG="$1"

  curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
    -d "chat_id=$CHAT_ID&parse_mode=html&text=$MSG" \
    -d "reply_to_message_id=$TOPIC_ID" \
    -d disable_web_page_preview=true
}

# Send TG file
send_file() {
  local FILE="$1"

  curl "https://api.telegram.org/bot$BOT_TOKEN/sendDocument" \
    -F chat_id="$CHAT_ID" \
    -F reply_to_message_id="$TOPIC_ID" \
    -F document=@"$FILE"
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

    send_msg "📦 <code>$ZIP_NAME</code>%0A🔐 <b>SHA256: </b><code>$KSHA256</code>%0A🔗 <b>Download:</b> <a href=\"$URL_ID\">$UPLOAD_HOST</a>"
  else
    send_msg "❌ Upload failed!"
  fi
}

# Upload to PixelDrain
pixeldrain_upload() {
  local FILE_PATH="$1"
  local FILE_NAME="${FILE_PATH##*/}"

  if [ -z "$PIXELDRAIN_API_TOKEN" ]; then
    send_msg "<b>❌ Upload failed: <i>PIXELDRAIN_API_TOKEN</i> not found!</b>"
    return 1
  fi

  RESPONSE=$(curl -T "$FILE_PATH" -u :$PIXELDRAIN_API_TOKEN https://pixeldrain.com/api/file/)

  PD_UPLOAD_ID=$(echo "$RESPONSE" | grep -Po '(?<="id":")[^\"]*')
  if [ -n "$PD_UPLOAD_ID" ]; then
    URL_ID="https://pixeldrain.com/u/$PD_UPLOAD_ID"
    send_msg "📦 <code>$ZIP_NAME</code>%0A🔐 <b>SHA256: </b><code>$KSHA256</code>%0A🔗 <b>Download:</b> <a href=\"$URL_ID\">$UPLOAD_HOST</a>"
  else
    send_msg "❌ Upload failed!"
    return 1
  fi
}

elapsed_time() {
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

# toolchain
case "$TOOLCHAIN" in
  AOSP)
    if [[ ! -d clang ]]; then
      AOSP_REV="r547379"
      mkdir -p clang && cd clang
      wget -q https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/master/clang-$AOSP_REV.tgz
      tar -xf clang-$AOSP_REV.tgz
      cd "$ROOT_DIR"
    fi
    TC_PATH="${ROOT_DIR}/clang/bin"
    ;;

  neutron)
    if [[ ! -d neutron_clang ]]; then
      mkdir -p neutron_clang && cd neutron_clang
      bash <(curl -s https://raw.githubusercontent.com/Neutron-Toolchains/antman/main/antman) -S
      cd "$ROOT_DIR"
    fi
    TC_PATH="${ROOT_DIR}/neutron_clang/bin"
    ;;

  zyc)
    if [[ ! -d zyc_clang ]]; then
      wget -q https://raw.githubusercontent.com/ZyCromerZ/Clang/main/Clang-main-lastbuild.txt
      V="$(cat Clang-main-lastbuild.txt)"
      wget -q "https://github.com/ZyCromerZ/Clang/releases/download/18.0.0-${V}-release/Clang-18.0.0-${V}.tar.gz"
      mkdir -p zyc_clang && tar -xf Clang-18.0.0-${V}.tar.gz -C zyc_clang
    fi
    TC_PATH="${ROOT_DIR}/zyc_clang/bin"
    ;;

  *)
    send_msg "❌ ERROR: Unknown toolchain: ${TOOLCHAIN}"
    exit 1
    ;;
esac

# Exports
export ARCH=arm64
export SUBARCH=arm64
export PATH="${TC_PATH}:$PATH"

# Kernel version
KERVER=$(make kernelversion)

# Out Dir
OUT_DIR="${ROOT_DIR}/out"
mkdir -p "${OUT_DIR}"

# Clean home
rm -f defc_log.txt build_log.txt

# Start build
START_TIME=$(date +%s)
send_msg "🚀 <b>Build started for</b> <i>$DEVICE</i>%0A📝 <i>N0kramel</i>%0A📱 <i>$KERVER</i>"

make O=out CC=clang vendor/${DEVICE}_defconfig &>defc_log.txt

if [ $? -ne 0 ]; then
  send_msg "❌ Build Failed!"
  send_file defc_log.txt
  exit 1
fi

make -j${JOBS} O=out CC=clang CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_COMPAT=arm-linux-gnueabi- LLVM=1 LLVM_IAS=1 &>build_log.txt

if [ $? -ne 0 ]; then
  send_msg "❌ Build Failed!"
  send_file build_log.txt
  exit 1
fi

END_TIME=$(date +%s)
BUILD_TIME=$(elapsed_time)

send_msg "✅ <b>Build completed</b>%0A⏱ <b>$BUILD_TIME</b>"

if ! [ -a "out/arch/arm64/boot/Image" ]; then
  send_msg "❌ ERROR: Kernel image not found!"
  exit 1
fi

# AK3
AK3_DIR="${ROOT_DIR}/AnyKernel3"
git clone --depth=1 https://github.com/GustavoMends/AnyKernel3.git -b ${DEVICE} ${AK3_DIR}

# Copy files
mv out/arch/arm64/boot/dtb.img out/arch/arm64/boot/dtb
mv out/arch/arm64/boot/dtb ${AK3_DIR}/
mv out/arch/arm64/boot/dtbo.img ${AK3_DIR}/
mv out/arch/arm64/boot/Image ${AK3_DIR}/
cd ${AK3_DIR}

# Kramel name
if [[ "${BUILD_TYPE}" == "BETA" ]]; then
  ZIP_NAME="N0kramel-${DEVICE}-${TM}-${COMMIT_HEAD}.zip"
else
  ZIP_NAME="N0kramel-${DEVICE}-${TM}.zip"
fi

# Zipping files
zip -r9 $ZIP_NAME *

# SHA256
KSHA256=$(sha256sum "$ZIP_NAME" | awk '{print $1}')

# Upload
case "${UPLOAD_HOST}" in
  telegram) send_file "$ZIP_NAME" ;;
  gofile) gofile_upload "$ZIP_NAME" ;;
  pixeldrain) pixeldrain_upload "$ZIP_NAME" ;;
  *) send_msg "❌ ERROR: Unknown upload host: ${UPLOAD_HOST}" ;;
esac
