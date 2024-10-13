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

# User vars
DEVICE="$1"
BUILD_TYPE="$2"

# ROM vars
ROM_DIR="$(pwd)"
OUT_DIR="$ROM_DIR/out/target/product/$DEVICE"

# CI
if [ -e $ROM_DIR/ids.txt ]; then
    FLAG_CI_BUILD=y
    CHAT_ID=$(awk "NR==1{print;exit}" ids.txt)
    BOT_TOKEN=$(awk "NR==2{print;exit}" ids.txt)
    TOPIC_ID=$(awk "NR==3{print;exit}" ids.txt)
fi

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
    esac
done

# Jobs
if [ "${FLAG_FULL_JOBS}" = 'y' ]; then
    JOBS="${ALL_PROCS}"
elif [ "${FLAG_CUSTOM_JOBS}" = 'y' ]; then
    JOBS="${CUSTOM_JOBS}"
else
    echo -e "${BLD_BLU}WARNING: No defined number of jobs! The default value is 16!!${RST}"
    JOBS=16
fi

# Send Telegram message
push_msg() {
    curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
         -d "chat_id=$CHAT_ID&parse_mode=html&text=$1" \
         -d "reply_to_message_id=$TOPIC_ID"
}

# Builder
building() {
    if [ "${FLAG_CI_BUILD}" = 'y' ]; then
        local start_time=$(date +%s)
        push_msg "🛠 CI | PixelOS (14)%0ADevice: $DEVICE%0ABuild type: $BUILD_TYPE"
    fi

    source build/envsetup.sh
    breakfast "$DEVICE" "$BUILD_TYPE"
    mka bacon -j "$JOBS"

    if [ "${FLAG_CI_BUILD}" = 'y' ]; then
        local end_time=$(date +%s)
        build_status $start_time $end_time
    else
        build_status
    fi
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
    if [ "${FLAG_CI_BUILD}" = 'y' ]; then
        local start_time=$1
        local end_time=$2
        build_time=$(count_build_time $start_time $end_time)
    fi

    BUILD_PACKAGE="$(find "$OUT_DIR" -name "PixelOS_$DEVICE-14.0-*.zip" -print -quit)"

    if [ -n "$BUILD_PACKAGE" ]; then
        if [ "${FLAG_CI_BUILD}" = 'y' ]; then
            BUILD_ID=$(basename $BUILD_PACKAGE)
            MD5_CHECK=$(md5sum $BUILD_PACKAGE | awk '{print $1}')
            push_msg "Build completed successfully%0ATotal time elapsed: <b>$build_time</b>"
        fi
        uploading
    else
        push_log
    fi
}

uploading() {
    case $UPLOAD_HOST in
        gofile)
            echo -e "${ORANGE}Starting upload to Gofile...${RST}"
            gofile_upload $BUILD_PACKAGE
            ;;
        *)
            echo -e "${BLD_BLU}Upload host not defined!${RST}"
            ;;
    esac
}

# Upload ROM package
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

        echo -e "${ORANGE}Done!${RST}"
        if [ "${FLAG_CI_BUILD}" = 'y' ]; then
            push_msg "Uploaded to Gofile%0A1. $BUILD_ID | <b>MD5: </b>$MD5_CHECK%0A1. Download: $URL_ID"
        else
            echo -e "${ORANGE}Download: $URL_ID${RST}"
        fi
    else
        echo -e "${RED}Upload failed!${RST}"
        if [ "${FLAG_CI_BUILD}" = 'y' ]; then
            push_msg "Upload failed!"
        fi
    fi
}

push_log() {
    LOG="$ROM_DIR/out/error.log"

    echo -e "${BLD_RED}Build failed!${RST}"
    if [ "${FLAG_CI_BUILD}" = 'y' ]; then
        push_msg "Build failed"
        curl -F chat_id="$CHAT_ID" -F reply_to_message_id="$TOPIC_ID" -F document=@"$LOG" "https://api.telegram.org/bot$BOT_TOKEN/sendDocument"
    else
        PAST_LOG="$(cat $LOG)"
        response=$(curl -s -d "$PAST_LOG" https://paste.crdroid.net/documents)
        KEY=$(echo "$response" | grep -Po '(?<="key":")[^"]*')
        echo -e "${BLD_RED}Log info: https://paste.crdroid.net/$KEY${RST}"
    fi
}

building
