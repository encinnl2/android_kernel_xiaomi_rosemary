#!/bin/bash
set -e

# Build kernel
make O=out ARCH=arm64 rosemary_defconfig
make -j$(nproc --all) CC=clang O=out ARCH=arm64 LLVM=1 LLVM_IAS=1 \
    LD=ld.lld AS=llvm-as AR=llvm-ar NM=llvm-nm OBJCOPY=llvm-objcopy \
    OBJDUMP=llvm-objdump READELF=llvm-readelf STRIP=llvm-strip \
    CROSS_COMPILE=aarch64-linux-gnu-

# Build external WiFi modules
build_mod() {
    local mod=$1 cfg=$2
    echo "Building $mod..."
    make -j$(nproc --all) ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- \
        CC=clang $cfg \
        -C $PWD/out M=$PWD/modules/$mod modules
}
build_mod rtl8188eu CONFIG_RTL8188EU=m
build_mod rtl8812au CONFIG_88XXAU=m
build_mod rtl88x2bu CONFIG_RTL8822BU=m

# Collect modules
mkdir -p $PWD/AnyKernel3/modules/system/lib/modules
find $PWD/modules -name "*.ko" -exec cp {} $PWD/AnyKernel3/modules/system/lib/modules/ \;

# Copy kernel image
cp $PWD/out/arch/arm64/boot/Image.gz-dtb $PWD/AnyKernel3/

# Create zip
cd $PWD/AnyKernel3
zip -r9 ../Orion-2.6-WiFi-Fix.zip * -x "*.git*" -x "README*"
cd $PWD

echo "Build complete: Orion-2.6-WiFi-Fix.zip"
