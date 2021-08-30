#!/bin/sh
# SPDX-License-Identifier: MIT

set -e
#set -x

CONFIGFS="/sys/kernel/config"
GADGET="$CONFIGFS/usb_gadget"
VID="0x1d6b"
PID="0x0104"
SERIAL="0123456789"
MANUF=$(hostname)
PRODUCT="UVC Gadget"

USBFILE=/home/root/usbstorage.img

BOARD=$(strings /proc/device-tree/model)

case $BOARD in
    "Renesas Salvator-X board based on r8a7795 ES1.x")
        UDC_USB2=e6590000.usb
        UDC_USB3=ee020000.usb

        UDC_ROLE2=/sys/devices/platform/soc/ee080200.usb-phy/role
        UDC_ROLE2=/dev/null #Not needed - always peripheral
        UDC_ROLE3=/sys/devices/platform/soc/ee020000.usb/role

        UDC=$UDC_USB2
        UDC_ROLE=$UDC_ROLE2
        ;;

    "TI OMAP4 PandaBoard-ES")
        UDC=`ls /sys/class/udc` # Should be musb-hdrc.0.auto
        UDC_ROLE=/dev/null # Not needed - peripheral enabled
        ;;

    *)
        UDC=`ls /sys/class/udc` # will identify the 'first' UDC
        UDC_ROLE=/dev/null # Not generic
        ;;
esac

echo "Detecting platform:"
echo "  board : $BOARD"
echo "  udc   : $UDC"

create_msd() {
    # Example usage:
    # create_msd <target config> <function name> <image file>
    # create_msd configs/c.1 mass_storage.usb0 /home/root/backing.img
    CONFIG=$1
    FUNCTION=$2
    BACKING_STORE=$3

    if [ ! -f $BACKING_STORE ]
    then
        echo "  Creating backing file"
        dd if=/dev/zero of=$BACKING_STORE bs=1M count=256 > /dev/null 2>&1
        mkfs.ext4 $BACKING_STORE > /dev/null 2>&1
        echo "  OK"
    fi

    echo "Creating Mass Storage gadget functionality : $FUNCTION"
    mkdir functions/$FUNCTION
    echo 1 > functions/$FUNCTION/stall
    echo $BACKING_STORE > functions/$FUNCTION/lun.0/file
    echo 1 > functions/$FUNCTION/lun.0/removable
    echo 0 > functions/$FUNCTION/lun.0/cdrom

    ln -s functions/$FUNCTION $CONFIG

    echo "OK"
}

delete_msd() {
    # Example usage:
    # delete_msd <target config> <function name>
    # delete_msd config/c.1 mass_storage.usb0
    CONFIG=$1
    FUNCTION=$2

    echo "Deleting Mass Storage gadget functionality : $FUNCTION"
    rm -f $CONFIG/$FUNCTION
    rmdir functions/$FUNCTION
    echo "OK"
}

create_frame() {
    # Example usage:
    # create_frame <function name> <width> <height> <format> <name>

    FUNCTION=$1
    WIDTH=$2
    HEIGHT=$3
    FORMAT=$4
    NAME=$5

    wdir=functions/$FUNCTION/streaming/$FORMAT/$NAME/${HEIGHT}p

    mkdir -p $wdir
    echo $WIDTH > $wdir/wWidth
    echo $HEIGHT > $wdir/wHeight
    echo $(( $WIDTH * $HEIGHT * 2 )) > $wdir/dwMaxVideoFrameBufferSize
    cat <<EOF > $wdir/dwFrameInterval
666666
1000000
5000000
EOF
}

create_uvc() {
    # Example usage:
    # create_uvc <target config> <function name>
    # create_uvc config/c.1 uvc.usb0
    CONFIG=$1
    FUNCTION=$2

    echo "Creating UVC gadget functionality : $FUNCTION"
    mkdir functions/$FUNCTION

    create_frame $FUNCTION 640 480 uncompressed u
    create_frame $FUNCTION 640 480 mjpeg mjpeg

    mkdir functions/$FUNCTION/streaming/header/h
    cd functions/$FUNCTION/streaming/header/h
    ln -s ../../uncompressed/u
    ln -s ../../mjpeg/mjpeg
    cd ../../class/fs
    ln -s ../../header/h
    cd ../../class/hs
    ln -s ../../header/h
    cd ../../class/ss
    ln -s ../../header/h
    cd ../../../control
    mkdir header/h
    ln -s header/h class/fs
    ln -s header/h class/ss
    cd ../../../

    # Set the packet size: uvc gadget max size is 3k...
    # echo 3072 > functions/$FUNCTION/streaming_maxpacket
    echo 2048 > functions/$FUNCTION/streaming_maxpacket
    # echo 1024 > functions/$FUNCTION/streaming_maxpacket

    ln -s functions/$FUNCTION $CONFIG

    echo "OK"
}

delete_uvc() {
    # Example usage:
    # delete_uvc <target config> <function name>
    # delete_uvc config/c.1 uvc.usb0
    CONFIG=$1
    FUNCTION=$2

    echo "Deleting UVC gadget functionality : $FUNCTION"
    rm $CONFIG/$FUNCTION

    rm functions/$FUNCTION/control/class/*/h
    rm functions/$FUNCTION/streaming/class/*/h
    rm functions/$FUNCTION/streaming/header/h/u
    rm functions/$FUNCTION/streaming/header/h/mjpeg
    rmdir functions/$FUNCTION/streaming/uncompressed/u/*/
    rmdir functions/$FUNCTION/streaming/uncompressed/u
    rmdir functions/$FUNCTION/streaming/mjpeg/mjpeg/*/
    rmdir functions/$FUNCTION/streaming/mjpeg/mjpeg
    rmdir functions/$FUNCTION/streaming/header/h
    rmdir functions/$FUNCTION/control/header/h
    rmdir functions/$FUNCTION

    echo "OK"
}

create_acm(){
    # Example usage:
    # create_acm <target config> <function name>
    # create_acm config/c.1 acm.usb0
    CONFIG=$1
    FUNCTION=$2

    echo "Creating ACM gadget functionality : $FUNCTION"
    mkdir functions/$FUNCTION

    ln -s functions/$FUNCTION $CONFIG

    echo "OK"
}

delete_acm() {
    # Example usage:
    # delete_acm <target config> <function name>
    # delete_acm config/c.1 acm.usb0
    CONFIG=$1
    FUNCTION=$2

    echo "Deleting ACM gadget functionality : $FUNCTION"
    rm -f $CONFIG/$FUNCTION
    rmdir functions/$FUNCTION
    echo "OK"
}

# Ethernet Adapter
#-------------------------------------------
create_rndis () {
    # Example usage:
    # create_rndis <target config> <function name>
    # create_rndis config/c.1 rndis.usb0
    CONFIG=$1
    FUNCTION=$2

    echo "Creating RNDIS gadget functionality : $FUNCTION"
    # Setup the OS Descriptors for our RNDIS device to be automatically installed
    mkdir -p os_desc
    # echo "0x80" > $CONFIG/bmAttributes
    echo 1  > os_desc/use
    echo 0xcd  > os_desc/b_vendor_code
    echo MSFT100 > os_desc/qw_sign

    mkdir functions/$FUNCTION
    # Allow the gadget to be used as a network device
    echo RNDIS  > functions/$FUNCTION/os_desc/interface.rndis/compatible_id
    echo 5162001 > functions/$FUNCTION/os_desc/interface.rndis/sub_compatible_id

    ln -s functions/$FUNCTION $CONFIG
    if [ ! -e os_desc/c.1 ]; then
    ln -s $CONFIG os_desc/
    fi
    if [ ! -e $CONFIG/$FUNCTION ]; then
    ln -s functions/$FUNCTION $CONFIG
    fi

    echo "**Please run ifconfig usb0 <ip> after rndis gadget created."
    echo "OK"
}

delete_rndis() {
    # Example usage:
    # delete_rndis <target config> <function name>
    # delete_rndis config/c.1 rndis.usb0
    CONFIG=$1
    FUNCTION=$2

    echo "Deleting RNDIS gadget functionality : $FUNCTION"
    rm -f os_desc/c.1
    rm -f $CONFIG/$FUNCTION
    rmdir functions/$FUNCTION
    echo "OK"
}

create_ecm(){
    # Example usage:
    # create_ecm <target config> <function name>
    # create_ecm config/c.1 ecm.usb0
    CONFIG=$1
    FUNCTION=$2

    echo "Creating ECM gadget functionality : $FUNCTION"
    mkdir functions/$FUNCTION
    # echo $MAC_HOST > functions/$FUNCTION/host_addr
    # echo $MAC_SELF > functions/$FUNCTION/dev_addr
    ln -s functions/$FUNCTION $CONFIG

    echo "**Please run ifconfig usb0 <ip> after ecm gadget created."
    echo "OK"
}

delete_ecm() {
    # Example usage:
    # delete_ecm <target config> <function name>
    # delete_ecm config/c.1 ecm.usb0
    CONFIG=$1
    FUNCTION=$2

    echo "Deleting ECM gadget functionality : $FUNCTION"
    rm -f $CONFIG/$FUNCTION
    rmdir functions/$FUNCTION
    echo "OK"
}

bind_udc() {
    udevadm settle -t 5 || :

    # Clear the UDC file if we have been here before
    # This avoids errors if we run this script twice
    # and allows us to essentially reset the interface if necessary
    if [[ $(< ./UDC) != "$UDC" ]]; then
    # We have not been here before (file does not match $str), so write the UDC fe
    # For some unknown reason we need to write, clear, then write the file again
    echo "Write $UDC to UDC"
    echo $UDC > ./UDC
    sync
    else                                                                            
    # We have been here before, so clear the UDC file first
    echo "Clear UDC"
    echo "" > ./UDC                                                               
    sync
    echo "Write $UDC to UDC"
    echo $UDC > ./UDC
    fi
    echo "Finish bind to UDC"
}

case "$1" in
    start)
        echo "Creating the USB gadget"
        #echo "Loading composite module"
        #modprobe libcomposite

        echo "Creating gadget directory g1"
        mkdir -p $GADGET/g1

        cd $GADGET/g1
        if [ $? -ne 0 ]; then
            echo "Error creating usb gadget in configfs"
            exit 1;
        else
            echo "OK"
        fi

        echo "Setting Vendor and Product ID's"
        echo $VID > idVendor
        echo $PID > idProduct
        echo "OK"

        echo "Setting Device class and protocol"
        echo 0x0100 > bcdDevice
        echo 0x0200 > bcdUSB
        echo 0xEF   > bDeviceClass
        echo 0x02   > bDeviceSubClass
        echo 0x01   > bDeviceProtocol
        echo "OK"

        echo "Setting English strings"
        mkdir -p strings/0x409
        echo $SERIAL > strings/0x409/serialnumber
        echo $MANUF > strings/0x409/manufacturer
        echo $PRODUCT > strings/0x409/product
        echo "OK"

        echo "Creating Config"
        mkdir configs/c.1
        mkdir configs/c.1/strings/0x409
        # echo 500   > configs/c.1/MaxPower
        echo "UVC" > configs/c.1/strings/0x409/configuration

        echo "Creating functions..."
        case "$2" in
            msd)
                create_msd configs/c.1 mass_storage.usb0 $USBFILE
                ;;
            uvc)
                create_uvc configs/c.1 uvc.usb0
                ;;
            acm)
                create_acm configs/c.1 acm.usb0
                ;;
            rndis)
                create_rndis configs/c.1 rndis.usb0
                ;;
            ecm)
                create_ecm configs/c.1 ecm.usb0
                ;;
            *)
                create_uvc configs/c.1 uvc.usb0
                ;;
        esac
        # create_msd configs/c.1 mass_storage.usb0 $USBFILE
        # create_uvc configs/c.1 uvc.usb0
        # create_uvc configs/c.1 uvc.usb1
        # create_acm configs/c.1 acm.usb0
        # create_rndis configs/c.1 rndis.usb0
        # create_ecm configs/c.1 ecm.usb0
        echo "OK"

        echo "Binding USB Device Controller"
        # echo $UDC > UDC
        bind_udc
        echo peripheral > $UDC_ROLE
        cat $UDC_ROLE
        echo "OK"
        ;;

    stop)
        echo "Stopping the USB gadget"

        set +e # Ignore all errors here on a best effort

        cd $GADGET/g1

        if [ $? -ne 0 ]; then
            echo "Error: no configfs gadget found" 
            exit 1;
        fi

        echo "Unbinding USB Device Controller"
        grep $UDC UDC && echo "" > UDC
        echo "OK"

        echo "Deleting functions..."
        case "$2" in
            msd)
                delete_msd configs/c.1 mass_storage.usb0
                ;;
            uvc)
                delete_uvc configs/c.1 uvc.usb0
                ;;
            acm)
                delete_acm configs/c.1 acm.usb0
                ;;
            rndis)
                delete_rndis configs/c.1 rndis.usb0
                ;;
            ecm)
                delete_ecm configs/c.1 ecm.usb0
                ;;
            *)
                delete_uvc configs/c.1 uvc.usb0
                ;;
        esac
        # delete_ecm configs/c.1 ecm.usb0
        # delete_rndis configs/c.1 rndis.usb0
        # delete_acm configs/c.1 acm.usb0
        # delete_uvc configs/c.1 uvc.usb1
        # delete_uvc configs/c.1 uvc.usb0
        # delete_msd configs/c.1 mass_storage.usb0
        echo "OK"
    
        echo "Clearing English strings"
        rmdir strings/0x409
        echo "OK"

        echo "Cleaning up configuration"
        rmdir configs/c.1/strings/0x409
        rmdir configs/c.1
        echo "OK"

        echo "Removing gadget directory"
        cd $GADGET
        rmdir g1
        cd /
        echo "OK"

        #echo "Disable composite USB gadgets"
        #modprobe -r libcomposite
        #echo "OK"
        ;;

    rebind)
        echo "Binding USB Device Controller"
        # echo $UDC > UDC
        bind_udc
        echo peripheral > $UDC_ROLE
        cat $UDC_ROLE
        echo "OK"
        ;;

    unbind)
        echo "Unbinding USB Device Controller"
        grep $UDC UDC && echo "" > UDC
        echo "OK"
        ;;

    *)
        echo "Usage : $0 {start|stop|rebind|unbind} <function>"
esac
