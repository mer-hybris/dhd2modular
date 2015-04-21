#!/bin/bash
# droid-hal device packaging converter: from monolithic to modular
# Copyright (c) 2015 Jolla Ltd.
# Contact: Simonas Leleiva <simonas.leleiva@jollamobile.com>

if [ -z $DEVICE ]; then
    echo 'Error: $DEVICE is undefined. Please run hadk'
    exit 1
fi
if [[ ! -d rpm/helpers && ! -d rpm/dhd ]]; then
    echo $0: launch this script from the $ANDROID_ROOT directory
    exit 1
fi

GITODO=sledges ## sed to mer-hybris once upstream
GITBMOD=dhd2modular ## sed to modular ---"---
GITCFGBMOD=$GITBMOD ## sed to master  ---"---

# utilities
. $ANDROID_ROOT/hybris/dhd2modular/util.sh

function usage() {
    echo "Usage: $0 COMMAND [TYPE]"
    echo "Create modular droid-hal-device repository layout from the old monolithic repo."
    echo
    echo "Supports partial argument matching like s mod -> snapshot modular."
    echo "  migrate                        create rpm-modular/ & Co. from monolithic rpm/"
    echo "  build-modular                  make a test build after migration."
    echo "  snapshot {monolithic|modular}  snapshot of a repo as tmp-dhd2modular-$TYPE/."
    echo "                                 Snapshot both types and then diff -r to find"
    echo "                                 differences if build above fails or device"
    echo "                                 doesn't boot."
}

function query_yes() {
    read -p " [Y/n]" REPLY
    REPLY=${REPLY:-y}
    if [[ ${REPLY:0:1} == [yY] ]]; then
        echo y
    fi
}

function migrate() {
    if [ -d rpm/dhd ]; then
        echo "rpm/dhd/ exists - already migrated. To nuke all, perform:"
        echo "rm -rf rpm/; mv rpm-monolithic rpm"
        exit 1
    fi
    set -e
    mv rpm rpm-monolithic
    mkdir rpm
    cd rpm
    git init
    git submodule add -b $GITBMOD https://github.com/$GITODO/droid-hal-device dhd
    DEVICE_PRETTY=$(grep "%define device_pretty " ../rpm-monolithic/droid-hal-$DEVICE.spec | cut -d ' ' -f3-)
    VENDOR_PRETTY=$(grep "%define vendor_pretty " ../rpm-monolithic/droid-hal-$DEVICE.spec | cut -d ' ' -f3-)
    if [[ -z $DEVICE_PRETTY || -z $VENDOR_PRETTY ]]; then
        echo "ERROR: Can't find device and/or vendor pretty names in ../rpm-monolithic/droid-hal-$DEVICE.spec"
        exit 1
    fi
    sed -e "s|@DEVICE@|$DEVICE|g" \
        -e "s|@VENDOR@|$VENDOR|g" \
        -e "s|@DEVICE_PRETTY@|$DEVICE_PRETTY|g" \
        -e "s|@VENDOR_PRETTY@|$VENDOR_PRETTY|g" \
        dhd/droid-hal-@DEVICE@.spec.template >droid-hal-$DEVICE.spec
    git add .
    git commit -m "[dhd2modular] Initial commit. Contributes to NEMO#788" 
    # Show anything else the user might be interested to transfer
    SPEC_EXTRAS=$(grep -vE "^$|\
^# device is the|\
^# eg mako =|\
^%define device|\
^# vendor is used|\
^%define vendor|\
^# Manufacturer|\
^%include rpm/droid-"\
        ../rpm-monolithic/droid-hal-$DEVICE.spec)
    if [[ -n $SPEC_EXTRAS ]]; then
        echo "--------------------------------------------------------------------------------"
        echo "These additonal entries were copied from the old rpm-monolithic/droid-hal-$DEVICE.spec"
        echo "over to the new .spec under rpm/. You should move all Requires and Provides to"
        echo "\$ANDROID_ROOT/hybris/droid-configs/droid-config-$DEVICE.spec"
        echo
        echo "$SPEC_EXTRAS"
        SPEC_EXTRAS=$(echo "$SPEC_EXTRAS" | sed -e 's/\\/\\\\/g' | sed -e :a -e '$!N;s/\n/\\n/;ta')
        sed -i -e "/^%include rpm\/dhd\/droid-.*$/i# Entries copied from rpm-monolithic\/droid-hal-$DEVICE.spec\n$SPEC_EXTRAS\n" droid-hal-$DEVICE.spec
    fi

    echo "-----------Migrating: droid-configs---------------------------------"
    cd ../hybris
    if [ -d droid-configs ]; then
        read -p "hybris/droid-configs already exists. Nuke and continue? [Y/n]" REPLY
        REPLY=${REPLY:-y}
        if [[ ${REPLY:0:1} == [yY] ]]; then
            rm -rf droid-configs
        else
            echo "Bailing out!"
            exit 1
        fi
    fi
    mkdir droid-configs
    cd droid-configs
    git init
    git submodule add -b $GITCFGBMOD https://github.com/$GITODO/droid-hal-configs droid-configs-device
    mkdir rpm
    sed -e "s|@DEVICE@|$DEVICE|g" \
        -e "s|@VENDOR@|$VENDOR|g" \
        -e "s|@DEVICE_PRETTY@|$DEVICE_PRETTY|g" \
        -e "s|@VENDOR_PRETTY@|$VENDOR_PRETTY|g" \
        droid-configs-device/droid-config-@DEVICE@.spec.template >rpm/droid-config-$DEVICE.spec
    cp -r $ANDROID_ROOT/rpm-monolithic/device-$VENDOR-$DEVICE-configs sparse
    mkdir patterns/
    cp -r $ANDROID_ROOT/rpm-monolithic/patterns/$DEVICE/* patterns/
    git add .
    git commit -m "[dhd2modular] Initial commit. Contributes to NEMO#788" 

    echo "-----------Migrating: droid-hal-version-$DEVICE---------------------------------"
    cd ..
    if [ -d droid-hal-version-$DEVICE ]; then
        read -p "hybris/droid-hal-version-$DEVICE already exists. Nuke and continue? [Y/n]" REPLY
        REPLY=${REPLY:-y}
        if [[ ${REPLY:0:1} == [yY] ]]; then
            rm -rf droid-hal-version-$DEVICE
        else
            echo "Bailing out!"
            exit 1
        fi
    fi
    mkdir droid-hal-version-$DEVICE
    cd droid-hal-version-$DEVICE
    git init
    git submodule add -b $GITCFGBMOD https://github.com/$GITODO/droid-hal-version
    mkdir rpm
    sed -e "s|@DEVICE@|$DEVICE|g" \
        -e "s|@VENDOR@|$VENDOR|g" \
        -e "s|@DEVICE_PRETTY@|$DEVICE_PRETTY|g" \
        -e "s|@VENDOR_PRETTY@|$VENDOR_PRETTY|g" \
        droid-hal-version/droid-hal-version-@DEVICE@.spec.template >rpm/droid-hal-version-$DEVICE.spec
    git add .
    git commit -m "[dhd2modular] Initial commit. Contributes to NEMO#788" 

    echo "-----------Checking how behind monolithic was with patterns...------"
    cd ..
    rpm/dhd/helpers/amibehind.sh -p

    echo "-----------------------------------DONE!----------------------------------------"
    echo "New repositories created under $ANDROID_ROOT:"
    echo "  rpm/"
    echo "  hybris/droid-configs"
    echo "  hybris/droid-hal-version-$DEVICE"
    echo "Your actions next:"
    if [[ -n $SPEC_EXTRAS ]]; then
        echo "* Move around and commit all changes across rpm/ and hybris/droid-configs"
        echo "  as per instructions above"
    fi
    echo "* Push all those repos above to your GitHub and ask on #sailfishos-porters for new"
    echo "  upstream (mer-hybris/) repositories to be created, then PR to them, thanks!"
    
    set +e
}

function build() {
    mb2 -t $VENDOR-$DEVICE-armv7hl -s rpm/droid-hal-$DEVICE.spec build

    mv -v RPMS/*$DEVICE* $LOCAL_REPO
    createrepo $LOCAL_REPO

    sb2 -t $VENDOR-$DEVICE-armv7hl -R -m sdk-install \
      ssu ar local-$DEVICE-hal-$1 file://$LOCAL_REPO

    sb2 -t $VENDOR-$DEVICE-armv7hl -R -m sdk-install \
      zypper ref

    if [ $1 == monolithic ]; then
        mb2 -t $VENDOR-$DEVICE-armv7hl \
          -s hybris/droid-hal-configs/rpm/droid-hal-configs.spec \
          build
        mv -v RPMS/*.rpm $LOCAL_REPO
    else
        cd hybris/droid-configs
        mb2 -t $VENDOR-$DEVICE-armv7hl \
          -s rpm/droid-config-$DEVICE.spec \
          build
        mv -v RPMS/*.rpm $LOCAL_REPO
        cd ../../
    fi

    createrepo $LOCAL_REPO
    sb2 -t $VENDOR-$DEVICE-armv7hl -R -m sdk-install \
      zypper ref
}

function rpm_snapshot() {
    LOCAL_REPO=$ANDROID_ROOT/$WORK/droid-$1-repo/$DEVICE
    mkdir -p $LOCAL_REPO
    rm -f $LOCAL_REPO/droid-hal-*rpm

    if [ $1 == monolithic ]; then
        if [ -d rpm/dhd ]; then
            echo "rpm/dhd/ exists - already migrated. To nuke all, perform:"
            echo "rm -rf rpm/; mv rpm-monolithic rpm"
            exit 1
        fi
    fi

    build $1

    cd $LOCAL_REPO
    mkdir rpm_contents
    cd rpm_contents
    find ../*.rpm -exec sh -c 'rpm2cpio {} | cpio -idv ' \; 2>&1 >/dev/null \
        | grep -v ' block' \
        | sort > $ANDROID_ROOT/$WORK/droid-$1-$DEVICE.files

    sb2 -t $VENDOR-$DEVICE-armv7hl -R -m sdk-install \
      ssu rr local-$DEVICE-hal-$1
}

if [ -z "$1" ]; then
    usage
    exit 1
elif [[ 'migrate' == $1* ]]; then
    migrate
elif [[ 'snapshot' == $1* ]]; then
    if [ -z "$2" ]; then
        usage
        exit 1
    elif [[ 'mo' == $2* ]]; then
        echo "Ambiguous argument $2: shortest abbrev. are mon and mod"
    elif [[ 'monolithic' == $2* ]]; then
        TYPE='monolithic'
    elif [[ 'modular' == $2* ]]; then
        TYPE='modular'
    fi

    WORK=tmp-dhd2modular
    rm -rf $WORK
    mkdir -p $WORK
 
    sb2 -t $VENDOR-$DEVICE-armv7hl -R -m sdk-install \
      ssu dr local-$DEVICE-hal

    rpm_snapshot $TYPE

    sb2 -t $VENDOR-$DEVICE-armv7hl -R -m sdk-install \
      ssu er local-$DEVICE-hal
elif [[ 'build-modular' == $1* ]]; then
    set -x
    if [ ! -d rpm/dhd ]; then
        echo "rpm/dhd/ does not exist, please run migrate first."
        exit 1
    fi
    LOCAL_REPO=$ANDROID_ROOT/droid-local-repo/$DEVICE
    rm -rf $LOCAL_REPO/*
    build 'modular'
    set +x
    echo "-------------------------------------------------------------------------------"
    read -p 'About to perform "Build HA Middleware Packages" HADK chapter. Press Enter to continue.'
    sb2 -t $VENDOR-$DEVICE-armv7hl -R -msdk-install ssu domain sales
    sb2 -t $VENDOR-$DEVICE-armv7hl -R -msdk-install ssu dr sdk

    sb2 -t $VENDOR-$DEVICE-armv7hl -R -msdk-install zypper ref -f
    sb2 -t $VENDOR-$DEVICE-armv7hl -R -msdk-install zypper -n install droid-hal-$DEVICE-devel

    rm -rf $MER_ROOT/devel/mer-hybris
    mkdir -p $MER_ROOT/devel/mer-hybris
    pushd $MER_ROOT/devel/mer-hybris

    buildmw libhybris || die
    sb2 -t $VENDOR-$DEVICE-armv7hl -R -msdk-build zypper -n rm mesa-llvmpipe
    buildmw "https://github.com/nemomobile/mce-plugin-libhybris.git" || die
    buildmw ngfd-plugin-droid-vibrator || die
    buildmw "https://github.com/mer-hybris/pulseaudio-modules-droid.git" rpm/pulseaudio-modules-droid.spec || die
    buildmw qt5-feedback-haptics-droid-vibrator || die
    buildmw qt5-qpa-hwcomposer-plugin || die
    buildmw "https://github.com/mer-hybris/qtscenegraph-adaptation.git" rpm/qtscenegraph-adaptation-droid.spec || die
    buildmw "https://github.com/mer-packages/qtsensors.git" || die
    buildmw "https://github.com/mer-packages/sensorfw.git" rpm/sensorfw-qt5-hybris.spec || die
    read -p '"Build HA Middleware Packages built". Press Enter to continue.'
    popd
    set -x

    cd hybris/droid-hal-version-$DEVICE
    mb2 -t $VENDOR-$DEVICE-armv7hl \
      -s rpm/droid-hal-version-$DEVICE.spec \
      build
    set +x
    mv -v RPMS/*.rpm $LOCAL_REPO
    cd ../../
    echo "----------------------DONE! Now proceed on creating the rootfs------------------"
fi

