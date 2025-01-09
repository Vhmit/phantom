#!/bin/bash

KERNEL_DIR="$(pwd)"

# User vars
export KBUILD_BUILD_HOST="ArchLinux"
export KBUILD_BUILD_USER="GustavoMends"

# Device vars
DEVICE="alioth"
DEFCONFIG="vendor/alioth_defconfig"

# DIRs
AK3_DIR=$KERNEL_DIR/AnyKernel3
OUTPUT_DIR="$KERNEL_DIR/out/arch/arm64/boot"
TC_DIR="$KERNEL_DIR/clang"

# TimeZone
DATE=$(TZ=America/Sao_Paulo date +"%Y%m%d-%T")
TM=$(date +"%F%S")

# Kernel Version
KERNEL_NAME=N0KRAMEL-$DEVICE-${TM}.zip

# Latest commit
COMMIT_HEAD=$(git log --oneline -1)

# Files
DTB=$OUTPUT_DIR/dtb
DTBO=$OUTPUT_DIR/dtbo.img
DTB_IMG=$OUTPUT_DIR/dtb.img
IMAGE=$OUTPUT_DIR/Image

# Arg parsing
for arg in "$@"; do
  case "$arg" in
    --neutron-clang)
      mkdir clang && cd clang
      bash <(curl -s https://raw.githubusercontent.com/Neutron-Toolchains/antman/main/antman) -S
      cd ..
      ;;
    --zyc-clang)
      mkdir clang && cd clang
      ZYC_VERSION=18.0.0
      wget https://raw.githubusercontent.com/ZyCromerZ/Clang/main/Clang-main-lastbuild.txt && V="$(cat Clang-main-lastbuild.txt)"
      wget -q https://github.com/ZyCromerZ/Clang/releases/download/${ZYC_VERSION}-$V-release/Clang-${ZYC_VERSION}-$V.tar.gz && tar -xf Clang-${ZYC_VERSION}-$V.tar.gz
      cd ..
      ;;
    --aosp-clang)
      AOSP_REVISION=r536225
      git clone --depth=1 https://gitlab.com/kei-space/clang/$AOSP_REVISION.git clang
      ;;
    --full-jobs)
      ALL_PROCS=$(nproc)
      FLAG_FULL_JOBS=y
      ;;
    --j*)
      CUSTOM_JOBS="${arg#--j}"
      FLAG_CUSTOM_JOBS=y
      ;;
  esac
done

clone_ak3() {
  rm -rf $AK3_DIR
  git clone --depth=1 https://github.com/GustavoMends/AnyKernel3 -b alioth $AK3_DIR
}

push_msg() {
  local message="$1"
  curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
    -d "chat_id=$CHAT_ID&parse_mode=html&text=$message" \
    -d "reply_to_message_id=$TOPIC_ID"
}

push() {
  curl -F chat_id="$CHAT_ID" -F reply_to_message_id="$TOPIC_ID" -F document=@"$1" \
    "https://api.telegram.org/bot$BOT_TOKEN/sendDocument"

}

build_kramel() {
  START=$(date +"%s")

  TC_NAME=$(${KERNEL_DIR}/clang/bin/clang --version | head -n 1 | perl -pe 's/\(http.*?\)//gs' | sed -e 's/  */ /g' -e 's/[[:space:]]*$//')
  push_msg "Build started"

  if [ "${FLAG_FULL_JOBS}" = 'y' ]; then
    JOBS="$ALL_PROCS"
  elif [ "${FLAG_CUSTOM_JOBS}" = 'y' ]; then
    JOBS="$CUSTOM_JOBS"
  else
    JOBS=12
  fi

  export ARCH=arm64
  export SUBARCH=arm64

  make O=out CC=clang $DEFCONFIG
  PATH="$TC_DIR/bin:${PATH}" make -j$JOBS O=out CC="clang" CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_COMPAT=arm-linux-gnueabi- LLVM=1 LLVM_IAS=1 &>build_log.txt

  if ! [ -a "$DTB_IMG" ] && [ -a "$DTBO" ] && [ -a "$IMAGE" ]; then
    push "build_log.txt" && push_msg "BUild Failed!"
    exit 1
  fi
  clone_ak3
}

function zipping() {

  mv $IMAGE $AK3_DIR
  mv $DTBO $AK3_DIR
  mv $DTB_IMG $DTB
  mv $DTB $AK3_DIR
  cd $AK3_DIR

  zip -r9 ${KERNEL_NAME} *
  push_msg "Build completed successfully%0ATotal time elapsed: <b> $(($DIFF / 60))min $(($DIFF % 60))s </b>"
  push "$KERNEL_NAME"
}

build_kramel
END=$(date +"%s")
DIFF=$(($END - $START))
zipping
