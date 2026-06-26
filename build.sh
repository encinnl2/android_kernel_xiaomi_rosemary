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

# Create post-fs-data.sh (load modules at boot)
cat > $KSUMOD_DIR/post-fs-data.sh << 'SCRIPT'
#!/system/bin/sh
for mod in /system/lib/modules/*.ko; do
    [ -f "$mod" ] && insmod "$mod" 2>/dev/null
done
SCRIPT
chmod +x $KSUMOD_DIR/post-fs-data.sh

# Create KSU-Next module zip
cd $KSUMOD_DIR
zip -r9 ../WiFi-Drivers-KSU-Next.zip * -x "*.git*"
cd $PWD

echo "Build complete: WiFi-Drivers-KSU-Next.zip"
