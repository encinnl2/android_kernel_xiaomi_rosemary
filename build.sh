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
    make -j$(nproc --all) ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- CC=clang \
        CONFIG_RTW_ADAPTIVITY_EN=n \
        CONFIG_RTW_NAPI=y \
        CONFIG_RTW_SKB_RECYCLE=y \
        CONFIG_DFS=n \
        CONFIG_RTW_CFG80211_STA_AP_MODE=y \
        CONFIG_RTW_CFG80211_MULTI_CHANNELED=y \
        EXTRA_CFLAGS="-O3 -march=armv8.2-a+crypto+crc -pipe -fomit-frame-pointer -funroll-loops -flto" \
        $cfg -C $PWD/out M=$PWD/modules/$mod modules
}

build_mod rtl8188eu CONFIG_RTL8188EU=m
build_mod rtl8812au CONFIG_88XXAU=m
build_mod rtl88x2bu CONFIG_RTL8822BU=m

find $PWD/modules -name "*.ko" -exec cp {} $KSUMOD_DIR/system/lib/modules/ \;

BUILD_DATE=$(date +%Y%m%d)
cat > $KSUMOD_DIR/module.prop << PROPROP
id=wifi_drivers
name=Realtek WiFi USB Drivers
version=v3.0-$BUILD_DATE
versionCode=$BUILD_DATE
author=encinnl2
description=Driver RTL8188EU(injection) RTL8812AU RTL88X2BU | O3+LTO+NAPI+dual_APmon+tuned
updateJson=https://raw.githubusercontent.com/encinnl2/android_kernel_xiaomi_rosemary/cip_susfs/update.json
PROPROP

cat > $KSUMOD_DIR/post-fs-data.sh << 'SCRIPT1'
#!/system/bin/sh
MODDIR=/system/lib/modules

if [ -f $MODDIR/8188eu.ko ]; then
    insmod $MODDIR/8188eu.ko \
        rtw_power_mgnt=0 \
        rtw_enusbss=0 \
        rtw_ips_mode=0 \
        rtw_ap_mode=1 \
        rtw_qos_opt_enable=0
fi

if [ -f $MODDIR/88XXau.ko ]; then
    insmod $MODDIR/88XXau.ko \
        rtw_power_mgnt=0 \
        rtw_enusbss=0 \
        rtw_ips_mode=0 \
        rtw_qos_opt_enable=0
fi

if [ -f $MODDIR/88x2bu.ko ]; then
    insmod $MODDIR/88x2bu.ko \
        rtw_power_mgnt=0 \
        rtw_enusbss=0 \
        rtw_ips_mode=0 \
        rtw_qos_opt_enable=0
fi
SCRIPT1
chmod +x $KSUMOD_DIR/post-fs-data.sh

cat > $KSUMOD_DIR/service.sh << 'SCRIPT2'
#!/system/bin/sh
sleep 5

MAXWAIT=30
for i in $(seq 1 $MAXWAIT); do
    iw dev 2>/dev/null | grep -q Interface && break
    sleep 1
done

for iface in $(iw dev 2>/dev/null | grep Interface | awk '{print $2}'); do
    phy=$(iw dev $iface info | awk '/wiphy/{print $2}')

    iw dev $iface set power_save off 2>/dev/null
    iw reg set US 2>/dev/null
    iw dev $iface set txpower fixed 3000 2>/dev/null

    [ -e /sys/class/net/$iface/device/power/control ] && \
        echo on > /sys/class/net/$iface/device/power/control

    iw phy $phy set rts 2500 2>/dev/null
    iw phy $phy set frag 1024 2>/dev/null
    iw phy $phy set bitrates legacy-2.4 12 18 24 36 48 54 2>/dev/null

    ifconfig $iface txqueuelen 2000 2>/dev/null
    iwconfig $iface retry limit 2 2>/dev/null
done

echo on > /sys/bus/usb/devices/usb1/power/control 2>/dev/null
echo on > /sys/bus/usb/devices/usb2/power/control 2>/dev/null

echo Y > /sys/module/usbcore/parameters/autosuspend 2>/dev/null
echo -1 > /sys/module/usbcore/parameters/autosuspend_delay_ms 2>/dev/null

echo 262144 > /proc/sys/net/core/rmem_max 2>/dev/null
echo 262144 > /proc/sys/net/core/wmem_max 2>/dev/null
echo 65536 > /proc/sys/net/core/rmem_default 2>/dev/null
echo 65536 > /proc/sys/net/core/netdev_max_backlog 2>/dev/null
echo 300 > /proc/sys/net/core/netdev_budget 2>/dev/null
echo bbr > /proc/sys/net/ipv4/tcp_congestion_control 2>/dev/null
SCRIPT2
chmod +x $KSUMOD_DIR/service.sh

cat > /tmp/chk_ksu_drivers.sh << 'SCRIPT3'
#!/system/bin/sh
echo "=== WiFi Driver Status ==="
lsmod | grep -E "8188|88XX|88x2" && echo "Module loaded OK" || echo "Module NOT loaded"
echo ""
echo "=== Interface ==="
iw dev 2>/dev/null | grep -E "Interface|type|channel|txpower" || echo "No interface"
echo ""
echo "=== Power Save ==="
iw dev $(iw dev 2>/dev/null | grep Interface | awk '{print $2}') get power_save 2>/dev/null
echo ""
echo "=== TxPower ==="
iw dev $(iw dev 2>/dev/null | grep Interface | awk '{print $2}') info 2>/dev/null | grep txpower
echo ""
echo "=== Reg Domain ==="
iw reg get 2>/dev/null | grep country
echo ""
echo "=== USB Power ==="
cat /sys/bus/usb/devices/usb1/power/control 2>/dev/null
echo ""
echo "=== Network Buffer ==="
cat /proc/sys/net/core/rmem_max
cat /proc/sys/net/core/netdev_max_backlog
SCRIPT3
cp /tmp/chk_ksu_drivers.sh $KSUMOD_DIR/check_drivers.sh
chmod +x $KSUMOD_DIR/check_drivers.sh

cd $KSUMOD_DIR
zip -r9 ../WiFi-Drivers-KSU-Next.zip * -x "*.git*"
cd $PWD

echo "Build complete: WiFi-Drivers-KSU-Next.zip"
