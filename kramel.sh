#!/bin/bash

# User vars
export KBUILD_BUILD_HOST="ArchLinux"
export KBUILD_BUILD_USER="GustavoMends"

# Dir
KERNEL_DIR=$(pwd)
OUT_DIR="out"
TC_DIR="$KERNEL_DIR/clang"

# Date
TM=$(date '+%Y%m%d-%H%M')

# Kramel name
if [ "${BUILD_TYPE}" = 'REL' ]; then
    ZIP_NAME="N0kramel-alioth-$TM"
else
    COMMIT_SHA="$(git rev-parse --short HEAD)"
    ZIP_NAME="N0kramel-alioth-$TM-$COMMIT_SHA"
fi

# Kramel Version
KERVER=$(make kernelversion)

clone_tc() {
    mkdir -p clang && cd clang

    case "$TC_TYPE" in
        AOSP)
            wget -q https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/master/clang-r547379.tgz
            tar -xf clang-r547379.tgz
            ;;
        Neutron)
            bash <(curl -s https://raw.githubusercontent.com/Neutron-Toolchains/antman/main/antman) -S
            ;;
        ZYC)
            wget https://raw.githubusercontent.com/ZyCromerZ/Clang/main/Clang-main-lastbuild.txt
            V="$(cat Clang-main-lastbuild.txt)"
            wget -q https://github.com/ZyCromerZ/Clang/releases/download/18.0.0-$V-release/Clang-18.0.0-$V.tar.gz
            tar -xf Clang-18.0.0-$V.tar.gz
            ;;
    esac

    cd ..
}

build_kernel() {
    export KBUILD_COMPILER_STRING=$(${KERNEL_DIR}/clang/bin/clang --version | head -n 1 | perl -pe 's/\(http.*?\)//gs' | sed -e 's/  */ /g' -e 's/[[:space:]]*$//')
    export COMMIT_HEAD=$(git log --oneline -1)

    export ARCH=arm64
    export SUBARCH=arm64
    export PATH="$TC_DIR/bin:$PATH"

    START_TIME=$(date +%s)
    send_msg "<b>CI Build Triggered</b>%0A<b>Kernel Version : </b><code>$KERVER</code>%0A<b>Compiler Used : </b><code>$KBUILD_COMPILER_STRING</code>%0A<b>Top Commit : </b><code>$COMMIT_HEAD</code>"
    make O=$OUT_DIR CC=clang vendor/alioth_defconfig &> defc_log.txt
    if [ $? -ne 0 ]; then
        send_msg "Build Failed!"
        send_file defc_log.txt
        exit 1
    fi

    make -j12 O=$OUT_DIR CC="clang" CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_COMPAT=arm-linux-gnueabi- LLVM=1 LLVM_IAS=1 &> build_log.txt
    if [ $? -ne 0 ]; then
        send_msg "Build Failed!"
        send_file build_log.txt
        exit 1
    fi

    END_TIME=$(date +%s)
    BUILD_TIME=$(elapsed_time)

    send_msg "Build completed successfully%0ATotal time elapsed: <b>$BUILD_TIME</b>"

    git clone --depth=1 https://github.com/GustavoMends/AnyKernel3.git -b alioth ak3
}

move_files() {
    if ! [ -a "out/arch/arm64/boot/Image" ]; then
        send_msg "Kernel image not found!"
        exit 1
    fi

    mv $OUT_DIR/arch/arm64/boot/dtb.img $OUT_DIR/arch/arm64/boot/dtb
    mv $OUT_DIR/arch/arm64/boot/dtb ak3/
    mv $OUT_DIR/arch/arm64/boot/dtbo.img ak3/
    mv $OUT_DIR/arch/arm64/boot/Image ak3/
}

zipping() {
    cd ak3
    zip -r9 $ZIP_NAME *
    if [ $? -eq 0 ]; then
        send_file $ZIP_NAME.zip
    else
        send_msg "Failed to zip file!"
        exit 1
    fi
}

send_msg() {
    local MSG="$1"
    curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
         -d "chat_id=$CHAT_ID&parse_mode=html&text=$MSG"
}

send_file() {
    local FILE="$1"
    curl -F chat_id="$CHAT_ID" -F document=@"$FILE" \
       "https://api.telegram.org/bot$BOT_TOKEN/sendDocument"
}

elapsed_time() {
    local ELAPSED=$((END_TIME - START_TIME))

    local HOURS=$((ELAPSED / 3600))
    local MINUTES=$(((ELAPSED % 3600) / 60))
    local SECONDS=$((ELAPSED % 60))

    if [ $HOURS -eq 0 ]; then
        if [ $SECONDS -le 9 ]; then
            echo "${MINUTES}min"
        else
            echo "${MINUTES}min ${SECONDS}s"
        fi
    else
        if [ $SECONDS -le 9 ]; then
            echo "${HOURS}h ${MINUTES}min"
        else
            echo "${HOURS}h ${MINUTES}min ${SECONDS}s"
        fi
    fi
}

clone_tc
build_kernel
move_files
zipping
