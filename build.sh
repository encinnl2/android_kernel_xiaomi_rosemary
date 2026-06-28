#!/bin/bash
set -e

KSUMOD_DIR="$PWD/WiFi-Drivers-KSU-Next"
rm -rf $KSUMOD_DIR
mkdir -p $KSUMOD_DIR/system/lib/modules

make O=out ARCH=arm64 rosemary_defconfig
make -j$(nproc --all) CC=clang O=out ARCH=arm64 LLVM=1 LLVM_IAS=1 LD=ld.lld AS=llvm-as AR=llvm-ar NM=llvm-nm OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump READELF=llvm-readelf STRIP=llvm-strip CROSS_COMPILE=aarch64-linux-gnu- modules_prepare

build_mod() {
    local mod=$1 cfg=$2
    echo "Building $mod..."
    make -j$(nproc --all) ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- CC=clang $cfg -C $PWD/out M=$PWD/modules/$mod modules
}

rm -rf modules/rtl8188eu
git clone --depth 1 https://github.com/aircrack-ng/rtl8188eus modules/rtl8188eu
sed -i 's/extern int console_suspend_enabled/extern bool console_suspend_enabled/' modules/rtl8188eu/os_dep/linux/usb_intf.c

build_mod rtl8188eu CONFIG_RTL8188EU=m
build_mod rtl8812au CONFIG_88XXAU=m
build_mod rtl88x2bu CONFIG_RTL8822BU=m

find $PWD/modules -name "*.ko" -exec cp {} $KSUMOD_DIR/system/lib/modules/ \;

BUILD_DATE=$(date +%Y%m%d)
cat > $KSUMOD_DIR/module.prop << PROPROP
id=wifi_drivers
name=Realtek WiFi USB Drivers
version=v1.1-$BUILD_DATE
versionCode=$BUILD_DATE
author=encinnl2
description=Driver untuk RTL8188EU (injection), RTL8812AU, RTL88X2BU WiFi USB dongle
updateJson=https://raw.githubusercontent.com/encinnl2/android_kernel_xiaomi_rosemary/cip_susfs/update.json
PROPROP

cat > $KSUMOD_DIR/post-fs-data.sh << 'SCRIPT1'
#!/system/bin/sh
MODDIR=/system/lib/modules
if [ -f $MODDIR/8188eu.ko ]; then
    insmod $MODDIR/8188eu.ko rtw_power_mgnt=0 rtw_enusbss=0 rtw_ips_mode=0 rtw_ap_mode=1 2>/dev/null
fi
if [ -f $MODDIR/88XXau.ko ]; then
    insmod $MODDIR/88XXau.ko rtw_power_mgnt=0 rtw_enusbss=0 rtw_ips_mode=0 2>/dev/null
fi
if [ -f $MODDIR/88x2bu.ko ]; then
    insmod $MODDIR/88x2bu.ko rtw_power_mgnt=0 rtw_enusbss=0 rtw_ips_mode=0 2>/dev/null
fi
SCRIPT1
chmod +x $KSUMOD_DIR/post-fs-data.sh

cat > $KSUMOD_DIR/service.sh << 'SCRIPT2'
#!/system/bin/sh
sleep 10

for i in $(seq 1 30); do
    if iw dev 2>/dev/null | grep -q Interface; then break; fi
    sleep 1
done

for iface in $(iw dev 2>/dev/null | grep Interface | awk '{print $2}'); do
    iw dev $iface set power_save off 2>/dev/null
    iw reg set US 2>/dev/null
    iw dev $iface set txpower fixed 3000 2>/dev/null
done
SCRIPT2
chmod +x $KSUMOD_DIR/service.sh

cd $KSUMOD_DIR
zip -r9 ../WiFi-Drivers-KSU-Next.zip * -x "*.git*"
cd $PWD

echo "Build complete: WiFi-Drivers-KSU-Next.zip"
