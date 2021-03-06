#!/bin/bash

function usage
{
    echo Usage:
    echo "  $(basename $0) manufacturer device [boot.img]"
    echo "  The boot.img argument is the extracted recovery or boot image."
    echo "  The boot.img argument should not be provided for devices"
    echo "  that have non standard boot images (ie, Samsung)."
    echo
    echo Example:
    echo "  $(basename $0) motorola sholes ~/Downloads/recovery-sholes.img"
    exit 0
}

MANUFACTURER=$1
DEVICE=$2
BOOTIMAGE=$3
HTCOVERLAY=$4
UNPACKBOOTIMG=$(which unpackbootimg)

if [ -z "$MANUFACTURER" ]
then
    usage
fi

if [ -z "$DEVICE" ]
then
    usage
fi

ANDROID_TOP=$(dirname $0)/../../../
pushd $ANDROID_TOP > /dev/null
ANDROID_TOP=$(pwd)
popd > /dev/null

TEMPLATE_DIR=$(dirname $0)
pushd $TEMPLATE_DIR > /dev/null
TEMPLATE_DIR=$(pwd)
popd > /dev/null

DEVICE_DIR=$ANDROID_TOP/device/$MANUFACTURER/$DEVICE

if [ ! -z "$BOOTIMAGE" ]
then
    if [ -z "$UNPACKBOOTIMG" ]
    then
        echo unpackbootimg not found. Is your android build environment set up and have the host tools been built?
        exit 0
    fi

    BOOTIMAGEFILE=$(basename $BOOTIMAGE)

    echo Output will be in $DEVICE_DIR
    mkdir -p $DEVICE_DIR

    TMPDIR=/tmp/bootimg
    rm -rf $TMPDIR
    mkdir -p $TMPDIR
    cp $BOOTIMAGE $TMPDIR
    pushd $TMPDIR > /dev/null
    unpackbootimg -i $BOOTIMAGEFILE > /dev/null
    mkdir ramdisk
    pushd ramdisk > /dev/null
    gunzip -c ../$BOOTIMAGEFILE-ramdisk.gz | cpio -i
    popd > /dev/null
    BASE=$(cat $TMPDIR/$BOOTIMAGEFILE-base)
    CMDLINE=$(cat $TMPDIR/$BOOTIMAGEFILE-cmdline)
    PAGESIZE=$(cat $TMPDIR/$BOOTIMAGEFILE-pagesize)
    export SEDCMD="s#__CMDLINE__#$CMDLINE#g"
    echo $SEDCMD > $TMPDIR/sedcommand
    cp $TMPDIR/$BOOTIMAGEFILE-zImage $DEVICE_DIR/kernel
    popd > /dev/null
else
    mkdir -p $DEVICE_DIR
    touch $DEVICE_DIR/kernel
    BASE=10000000
    CMDLINE=no_console_suspend
    PAGESIZE=00000800
    export SEDCMD="s#__CMDLINE__#$CMDLINE#g"
    echo $SEDCMD > $TMPDIR/sedcommand
fi

for file in $(find $TEMPLATE_DIR -name '*.template')
do
    OUTPUT_FILE=$DEVICE_DIR/$(basename $(echo $file | sed s/\\.template//g))
    cat $file | sed s/__DEVICE__/$DEVICE/g | sed s/__MANUFACTURER__/$MANUFACTURER/g | sed -f $TMPDIR/sedcommand | sed s/__BASE__/$BASE/g | sed s/__PAGE_SIZE__/$PAGESIZE/g > $OUTPUT_FILE
done

if [ ! -z "$TMPDIR" ]
then
    RECOVERY_FSTAB=$TMPDIR/ramdisk/etc/recovery.fstab
    if [ -f "$RECOVERY_FSTAB" ]
    then
        cp $RECOVERY_FSTAB $DEVICE_DIR/recovery.fstab
    fi
fi


mv $DEVICE_DIR/device.mk $DEVICE_DIR/device_$DEVICE.mk

#remove the size restrictions on the partitions - just go with it
sed -i '/^BOARD_.*_PARTITION_SIZE/d' $DEVICE_DIR/BoardConfig.mk

#add a variable to invert volume keys on devices
echo "#BOARD_HAS_INVERTED_VOLUME := true" >> $DEVICE_DIR/BoardConfig.mk

#add a lunch combo for the new device setup.
echo "add_lunch_combo full_$DEVICE-eng" > $DEVICE_DIR/vendorsetup.sh

#add an import for htc-overlay if asked
if [ ! -z "$HTCOVERLAY" ]; then
  echo "Adding HTC OVERLAY to BoardConfig.mk..."
  echo " " >> $DEVICE_DIR/BoardConfig.mk
  echo " " >> $DEVICE_DIR/BoardConfig.mk
  echo "#import HTC OVERLAY" >> $DEVICE_DIR/BoardConfig.mk
  echo "-include device/raidzero/htc-overlay/BoardConfig.mk" >> $DEVICE_DIR/BoardConfig.mk
fi

echo Done!
echo Use the following command to set up your build environment:
echo '  'lunch full_$DEVICE-eng
