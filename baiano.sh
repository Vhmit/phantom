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
CUSTOM_PROCS="18"

# ROM vars
ROM_DIR="$(pwd)"
OUT_DIR="$ROM_DIR/out/target/product/$DEVICE"
LUNCH_FLAVOR="aosp_$DEVICE-$BUILD_TYPE"

for arg in "$@"; do
    case "$arg" in
        --mclean)
            echo -e "${BLD_BLU}Cleaning all compiled files left from old builds...${RST}"
            rm -rf "$ROM_DIR/out"
            echo -e "${BLD_BLU}Done!${RST}"
            ;;
        --full-proc)
            if [ "$(uname -s)" = 'Darwin' ]; then
                ALL_PROCS=$(sysctl -n machdep.cpu.core_count)
            else
                ALL_PROCS=$(grep -c '^processor' /proc/cpuinfo)
            fi
            JOBS="$ALL_PROCS"
            ;;
        --upload-gofile)
            UPLOAD_HOST="gofile"
            ;;
        --upload-pixeldrain)
            UPLOAD_HOST="pixeldrain"
            ;;
    esac
done

[ -z "$JOBS" ] && JOBS="$CUSTOM_PROCS"

# Builder
building() {
    source build/envsetup.sh
    lunch "$LUNCH_FLAVOR"
    mka bacon -j "$JOBS"
}

# Build status
build_status() {
    BUILD_PACKAGE="$(find "$OUT_DIR" -name "PixelOS_$DEVICE-14.0-*.zip" -print -quit)"

    if [ -n "$BUILD_PACKAGE" ]; then
        echo -e "${GRN}Package Complete: $BUILD_PACKAGE${RST}"
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

    echo -e "${LIGHT_GREEN}Done!"
    echo -e "${LIGHT_GREEN}Download: https://pixeldrain.com/u/$FILE_ID${RST}"
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
    echo -e "${ORANGE}Done!${RST}"
    echo -e "${ORANGE}Download: $URL_ID${RST}"
    else
    echo -e "${RED}Upload failed!${RST}"
    fi
}

push_buildlog() {
    BUILD_LOG="$(cat $ROM_DIR/out/error.log)"
    response=$(curl -s -d "$BUILD_LOG" https://paste.crdroid.net/documents)
    KEY=$(echo "$response" | grep -Po '(?<="key":")[^"]*')

    echo -e "${BLD_RED}Build failed!${RST}"
    echo -e "${BLD_RED}Log info: https://paste.crdroid.net/$KEY${RST}"
}

building
build_status
