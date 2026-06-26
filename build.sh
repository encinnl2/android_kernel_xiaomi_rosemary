#!/bin/bash
set -e

KSUMOD_DIR="$PWD/WiFi-Drivers-KSU-Next"
rm -rf $KSUMOD_DIR
mkdir -p $KSUMOD_DIR/system/lib/modules

# Configure kernel (minimal)
make O=out ARCH=arm64 rosemary_defconfig
make -j$(nproc --all) CC=clang O=out ARCH=arm64 LLVM=1 LLVM_IAS=1     LD=ld.lld AS=llvm-as AR=llvm-ar NM=llvm-nm OBJCOPY=llvm-objcopy     OBJDUMP=llvm-objdump READELF=llvm-readelf STRIP=llvm-strip     CROSS_COMPILE=aarch64-linux-gnu- modules_prepare

# Build external WiFi modules
build_mod() {
    local mod=$1 cfg=$2
    echo "Building $mod..."
    make -j$(nproc --all) ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-         CC=clang $cfg         -C $PWD/out M=$PWD/modules/$mod modules
}
build_mod rtl8188eu CONFIG_RTL8188EU=m
build_mod rtl8812au CONFIG_88XXAU=m
build_mod rtl88x2bu CONFIG_RTL8822BU=m

# Copy .ko files to module directory
find $PWD/modules -name "*.ko" -exec cp {} $KSUMOD_DIR/system/lib/modules/ \;

# Create module.prop
cat > $KSUMOD_DIR/module.prop << 'EOF'
id=wifi_drivers
name=Realtek WiFi USB Drivers
version=1.0
versionCode=1
author=encinnl2
description=Driver untuk RTL8188EU, RTL8812AU, RTL88X2BU WiFi USB dongle
EOF

# Create post-fs-data.sh (load modules at boot with optimized parameters)
cat > $KSUMOD_DIR/post-fs-data.sh << 'SCRIPT'
#!/system/bin/sh

# Load each WiFi module with optimized performance parameters
# rtw_power_mgnt=0  -> Disable power saving for lowest latency
# rtw_enusbss=0     -> Disable USB selective suspend
# rtw_ips_mode=0    -> Disable Idle Power Save mode

MODDIR=/system/lib/modules

# RTL8188EU
if [ -f $MODDIR/8188eu.ko ]; then
    insmod $MODDIR/8188eu.ko \
        rtw_power_mgnt=0 \
        rtw_enusbss=0 \
        rtw_ips_mode=0 2>/dev/null
fi

# RTL8812AU (module name: 88XXau.ko)
if [ -f $MODDIR/88XXau.ko ]; then
    insmod $MODDIR/88XXau.ko \
        rtw_power_mgnt=0 \
        rtw_enusbss=0 \
        rtw_ips_mode=0 2>/dev/null
fi

# RTL88X2BU (with BT coexistence)
if [ -f $MODDIR/88x2bu.ko ]; then
    insmod $MODDIR/88x2bu.ko \
        rtw_power_mgnt=0 \
        rtw_enusbss=0 \
        rtw_ips_mode=0 2>/dev/null
fi
SCRIPT
chmod +x $KSUMOD_DIR/post-fs-data.sh

# Create service.sh (runtime optimizations after boot)
cat > $KSUMOD_DIR/service.sh << 'SCRIPT'
#!/system/bin/sh

# Wait for WiFi interface to appear
for i in $(seq 1 30); do
    if iw dev 2>/dev/null | grep -q Interface; then
        break
    fi
    sleep 1
done

# Apply runtime optimizations to all wlan interfaces
for iface in $(iw dev 2>/dev/null | grep Interface | awk '{print $2}'); do
    # Disable power saving for max performance
    iw dev $iface set power_save off 2>/dev/null
done
SCRIPT
chmod +x $KSUMOD_DIR/service.sh

# Create KSU-Next module zip
cd $KSUMOD_DIR
zip -r9 ../WiFi-Drivers-KSU-Next.zip * -x "*.git*"
cd $PWD

echo "Build complete: WiFi-Drivers-KSU-Next.zip"
