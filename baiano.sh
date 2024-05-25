#!/bin/bash
#

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

# Token
BOT_TOKEN=""
PD_KEY=""

# Chat ID
CHAT_ID=""
TOPIC_ID=""

# User vars
DEVICE="$1"
AOSP_TAG="$2"
BUILD_TYPE="$3"
LUNCH_FLAVOR="aosp_$DEVICE-$AOSP_TAG-$BUILD_TYPE"

# ROM vars
ROM_DIR="$(pwd)"
OUT_DIR="$ROM_DIR/out/target/product/$DEVICE"

for arg in "$@"; do
    case "$arg" in
        --mclean)
            echo -e "${BLD_BLU}Cleaning all compiled files left from old builds...${RST}"
            rm -rf "$ROM_DIR/out"
            echo -e "${BLD_BLU}Done!${RST}"
            ;;
        --full-jobs)
            if [ "$(uname -s)" = 'Darwin' ]; then
                ALL_PROCS=$(sysctl -n machdep.cpu.core_count)
            else
                ALL_PROCS=$(grep -c '^processor' /proc/cpuinfo)
            fi
            FLAG_FULL_JOBS=y
            ;;
        --j*)
            CUSTOM_JOBS="${arg#--j}"
            FLAG_CUSTOM_JOBS=y
            ;;
        --upload-gofile)
            UPLOAD_HOST="gofile"
            ;;
        --upload-pixeldrain)
            UPLOAD_HOST="pixeldrain"
            ;;
    esac
done

if [ "${FLAG_FULL_JOBS}" = 'y' ]; then
    JOBS="${ALL_PROCS}"
elif [ "${FLAG_CUSTOM_JOBS}" = 'y' ]; then
    JOBS="${CUSTOM_JOBS}"
else
    echo -e "${BLD_BLU}WARNING: No defined number of jobs! The default value is 8!!${RST}"
    JOBS=8
fi

# Send Telegram message
push_msg() {
    curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" -d "chat_id=$CHAT_ID&parse_mode=html&text=$1" -d "reply_to_message_id=$TOPIC_ID"
}

# Builder
building() {
    local start_time=$(date +%s)
    push_msg "🛠 CI | PixelOS (14)%0ADevice: $DEVICE%0ALunch flavor: $LUNCH_FLAVOR"

    source build/envsetup.sh
    lunch "$LUNCH_FLAVOR"
    mka bacon -j "$JOBS"

    local end_time=$(date +%s)
    build_status $start_time $end_time
}

# Build time
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
    local start_time=$1
    local end_time=$2
    build_time=$(count_build_time $start_time $end_time)

    BUILD_PACKAGE="$(find "$OUT_DIR" -name "PixelOS_$DEVICE-14.0-*.zip" -print -quit)"

    if [ -n "$BUILD_PACKAGE" ]; then
        BUILD_ID=$(basename $BUILD_PACKAGE)
        SHA256SUM_CHECK=$(basename $(sha256sum $BUILD_PACKAGE))
        push_msg "build completed sucessfully%0ATotal time elapsed: <b>$build_time</b>"
        uploading
    else
        push_buildlog
    fi
}

uploading() {
    # Upload 
	case $UPLOAD_HOST in

		# Gofile
		gofile)
			echo -e "${ORANGE}Starting upload to Gofile..."
			gofile_upload $BUILD_PACKAGE
			;;

		# PixelDrain
		pixeldrain)
			echo -e "${LIGHT_GREEN}Starting upload to PixelDrain..."
			pdrain_upload $BUILD_PACKAGE
			;;

		*)
			echo -e "${BLD_BLU}Upload host not defined!${RST}"
			;;
	esac
}

# Upload ROM package
pdrain_upload() {
    local FILE_PATH="$1"
    local FILE_NAME="${FILE_PATH##*/}"
    
    local response
    response=$(curl -# -F "name=$FILE_NAME" -F "file=@$FILE_PATH" "https://pixeldrain.com/api/file")

    local FILE_ID
    FILE_ID=$(echo "$response" | grep -Po '(?<="id":")[^"]*')

    echo -e "${LIGHT_GREEN}Done!${RST}"
    push_msg "Uploaded to PixelDrain%0A1. $BUILD_ID | <b>SHA256: </b>$SHA256SUM_CHECK%0A2. Download: https://pixeldrain.com/u/$FILE_ID"
}

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
    GOMD5=$(echo "$response" | grep -Po '(?<="md5":")[^"]*')
    echo -e "${ORANGE}Done!${RST}"
    push_msg "Uploaded to Gofile%0A1. $BUILD_ID | <b>SHA256: </b>$SHA256SUM_CHECK</b>%0A2. Download: $URL_ID"
    else
    echo -e "${RED}Upload failed!${RST}"
    push_msg "Upload failed!"
    fi
}

push_buildlog() {
    BUILD_LOG="$(cat $ROM_DIR/out/error.log)"
    response=$(curl -s -d "$BUILD_LOG" https://paste.crdroid.net/documents)
    KEY=$(echo "$response" | grep -Po '(?<="key":")[^"]*')

    push_msg "Build failed!%0ALog info: https://paste.crdroid.net/$KEY"
}

building
