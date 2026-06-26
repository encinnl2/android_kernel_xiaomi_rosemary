#!/bin/bash
set -e

KSUMOD_DIR="$PWD/WiFi-Drivers-KSU-Next"
rm -rf $KSUMOD_DIR
mkdir -p $KSUMOD_DIR/system/lib/modules

make O=out ARCH=arm64 rosemary_defconfig
make -j$(nproc --all) CC=clang O=out ARCH=arm64 LLVM=1 LLVM_IAS=1     LD=ld.lld AS=llvm-as AR=llvm-ar NM=llvm-nm OBJCOPY=llvm-objcopy     OBJDUMP=llvm-objdump READELF=llvm-readelf STRIP=llvm-strip     CROSS_COMPILE=aarch64-linux-gnu- modules_prepare

# Build RTL8188EU - use aircrack-ng fork with injection support
build_mod() {
    local mod=$1 cfg=$2
    echo "Building $mod..."
    make -j$(nproc --all) ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-         CC=clang $cfg         -C $PWD/out M=$PWD/modules/$mod modules
}

# Clone aircrack-ng 8188eu driver (injection patched)
rm -rf modules/rtl8188eu
git clone --depth 1 https://github.com/aircrack-ng/rtl8188eus modules/rtl8188eu
build_mod rtl8188eu CONFIG_RTL8188EU=m

build_mod rtl8812au CONFIG_88XXAU=m
build_mod rtl88x2bu CONFIG_RTL8822BU=m

find $PWD/modules -name "*.ko" -exec cp {} $KSUMOD_DIR/system/lib/modules/ \;

cat > $KSUMOD_DIR/module.prop << 'EOF'
id=wifi_drivers
name=Realtek WiFi USB Drivers
version=1.0
versionCode=1
author=encinnl2
description=Driver untuk RTL8188EU, RTL8812AU, RTL88X2BU WiFi USB dongle
EOF

cat > $KSUMOD_DIR/post-fs-data.sh << 'SCRIPT'
#!/system/bin/sh
MODDIR=/system/lib/modules

if [ -f $MODDIR/8188eu.ko ]; then
    insmod $MODDIR/8188eu.ko \
        rtw_power_mgnt=0 \
        rtw_enusbss=0 \
        rtw_ips_mode=0 \
        rtw_ap_mode=1 2>/dev/null
fi

if [ -f $MODDIR/88XXau.ko ]; then
    insmod $MODDIR/88XXau.ko \
        rtw_power_mgnt=0 \
        rtw_enusbss=0 \
        rtw_ips_mode=0 2>/dev/null
fi

if [ -f $MODDIR/88x2bu.ko ]; then
    insmod $MODDIR/88x2bu.ko \
        rtw_power_mgnt=0 \
        rtw_enusbss=0 \
        rtw_ips_mode=0 2>/dev/null
fi
