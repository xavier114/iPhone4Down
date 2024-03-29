#!/bin/bash
trap "Clean" EXIT
trap "Clean; exit 1" INT TERM

if [[ $1 != "NoColor" && $2 != "NoColor" ]]; then
    Color_R=$(tput setaf 9)
    Color_G=$(tput setaf 10)
    Color_B=$(tput setaf 12)
    Color_Y=$(tput setaf 11)
    Color_N=$(tput sgr0)
fi

Clean() {
    rm -rf iP*/ shsh/ tmp/ iBoot *_iPhone3,1_7.1.2-*.shsh2 FirmwareBundles src
}

Echo() {
    echo "${Color_B}$1 ${Color_N}"
}

Error() {
    echo -e "\n${Color_R}[Error] $1 ${Color_N}"
    [[ -n $2 ]] && echo "${Color_R}* $2 ${Color_N}"
    echo
    exit 1
}

Input() {
    echo "${Color_Y}[Input] $1 ${Color_N}"
}

Log() {
    echo "${Color_G}[Log] $1 ${Color_N}"
}

Main() {
    clear
    Echo "******* iPhone4Down *******"
    Echo "* Downgrader script by LukeZGD"
    Echo "* This script uses ch3rryflower by dora2iOS"
    echo

    cherrymac="./resources/ch3rryflower/Tools/macos/UNTETHERED"
    if [[ $OSTYPE == "linux"* ]]; then
        . /etc/os-release 2>/dev/null
        platform="linux"
        platformver="$PRETTY_NAME"
        bspatch="$(which bspatch)"
        cherry="./resources/ch3rryflower/Tools/ubuntu/UNTETHERED"
        idevicerestore="sudo LD_LIBRARY_PATH=./resources/lib ./resources/tools/idevicerestore_linux"
        pwnedDFU="sudo $cherry/pwnedDFU"
        python="$(which python2)"
        ipwndfu="sudo $python ipwndfu"
        xmlstarlet="$(which xmlstarlet)"

    elif [[ $OSTYPE == "darwin"* ]]; then
        platform="macos"
        platformver="${1:-$(sw_vers -productVersion)}"
        bspatch="/usr/bin/bspatch"
        cherry="$cherrymac"
        idevicerestore="./resources/tools/idevicerestore_macos"
        pwnedDFU="$cherry/pwnedDFU"
        python="/usr/bin/python"
        ipwndfu="$python ipwndfu"
        xmlstarlet=/
    fi
    expect="$(which expect)"
    git="$(which git)"
    ideviceenterrecovery="./resources/libimobiledevice_$platform/ideviceenterrecovery"
    ideviceinfo="./resources/libimobiledevice_$platform/ideviceinfo"
    ipsw="./resources/tools/ipsw_$platform"
    irecoverychk="./resources/libimobiledevice_$platform/irecovery"
    irecovery="$irecoverychk"
    [[ $platform == "linux" ]] && irecovery="sudo LD_LIBRARY_PATH=./resources/lib $irecovery"
    partialzip="./resources/tools/partialzip_$platform"
    tsschecker="resources/tools/tsschecker_$platform"

    if [[ $EUID == 0 ]]; then
        Error "Running the script as root is not allowed."
    fi

    if [[ ! -d ./resources ]]; then
        Error "resources folder cannot be found. Replace resources folder and try again" \
        "If resources folder is present try removing spaces from path/folder name"
    fi

    if [[ ! $platform ]]; then
        Error "Platform unknown/not supported."
    fi

    chmod +x ./resources/*.sh ./resources/tools/*
    if [[ $? != 0 ]]; then
        Error "A problem with file permissions has been detected, cannot proceed."
    fi

    Log "Checking Internet connection..."
    ping -c1 8.8.8.8 >/dev/null
    if [[ $? != 0 ]]; then
        Error "Please check your Internet connection before proceeding."
    fi

    if [[ $(uname -m) != "x86_64" ]]; then
        Error "Only 64-bit (x86_64) distributions are supported."
    fi

    if [[ $1 == "Install" || -z $bspatch || ! -e $ideviceinfo || ! -e $irecoverychk ||
          ! -e $ideviceenterrecovery || -z $python || -z $expect || -z $xmlstarlet ||
          ! -d ./resources/libimobiledevice_$platform ]]; then
        if [[ ! -e $ideviceinfo || ! -e $irecoverychk ||
              ! -e $ideviceenterrecovery ]]; then
            rm -rf ./resources/libimobiledevice_$platform
        fi
        InstallDepends
    fi

    if [[ ! -d resources/ch3rryflower ]]; then
        mkdir tmp 2>/dev/null
        cd tmp
        Log "Downloading ch3rryflower..."
        SaveFile https://github.com/dora2-iOS/ch3rryflower/archive/316d2cdc5351c918e9db9650247b91632af3f11f.zip ch3rryflower.zip 790d56db354151b9740c929e52c097ba57f2929d
        cd ../resources
        unzip -q ../tmp/ch3rryflower.zip -d .
        mv ch3rryflower* ch3rryflower
        cd ..
    fi
    SaveExternal ipwndfu

    Log "Running on platform: $platform ($platformver)"
    Log "Finding device in Normal mode..."
    ideviceinfo2=$($ideviceinfo -s)
    if [[ $? != 0 ]]; then
        Log "Finding device in DFU/recovery mode..."
        [[ $platform == "linux" ]] && Echo "* Enter root password of your PC when prompted"
        irecovery2=$($irecovery -q 2>/dev/null | grep 'MODE' | cut -c 7-)
    fi
    [[ $irecovery2 == "DFU" ]] && DFUDevice=1
    [[ $irecovery2 == "Recovery" ]] && RecoveryDevice=1

    if [[ $DFUDevice == 1 || $RecoveryDevice == 1 ]]; then
        ProdCut=7
        ProductType=$($irecovery -qv 2>&1 | grep "iP" | cut -c 14-)
        [[ $(echo $ProductType | cut -c 3) == 'h' ]] && ProdCut=9
        ProductType=$(echo $ProductType | cut -c -$ProdCut)
        UniqueChipID=$((16#$(echo $($irecovery -q | grep 'ECID' | cut -c 7-) | cut -c 3-)))
    else
        ProductType=$(echo "$ideviceinfo2" | grep 'ProductType' | cut -c 14-)
        [[ ! $ProductType ]] && ProductType=$($ideviceinfo | grep 'ProductType' | cut -c 14-)
        ProductVer=$(echo "$ideviceinfo2" | grep 'ProductVer' | cut -c 17-)
        VersionDetect=$(echo $ProductVer | cut -c 1)
        UniqueChipID=$(echo "$ideviceinfo2" | grep 'UniqueChipID' | cut -c 15-)
        UniqueDeviceID=$(echo "$ideviceinfo2" | grep 'UniqueDeviceID' | cut -c 17-)
    fi
    if [[ ! $UniqueChipID ]]; then
        Error "No device detected."
    elif [[ $ProductType != iPhone3,1 ]]; then
        Error "Your device $ProductType is not supported."
    fi

    iBSSURL=http://appldnld.apple.com/iOS7.1/031-4812.20140627.cq6y8/iPhone3,1_7.1.2_11D257_Restore.ipsw
    iBSS="iBSS.n90ap.RELEASE"

    Clean
    mkdir tmp

    if [[ $DFUDevice != 1 && $RecoveryDevice != 1 ]]; then
        Log "Device in normal mode detected."
        Echo "* The device needs to be in recovery/DFU mode before proceeding."
        read -p "$(Input 'Send device to recovery mode? (y/N):')" Jailbroken
        if [[ $Jailbroken == y || $Jailbroken == Y ]]; then
            Recovery
        else
            exit 0
        fi
    elif [[ $RecoveryDevice == 1 ]]; then
        Recovery
    fi

    if [[ $DFUDevice == 1 && $pwnDFUDevice != 1 ]]; then
        Log "Device in DFU mode detected."
        EnterPwnDFU
    fi

    if [[ $1 && $1 != 'NoColor' ]]; then
        Mode="$1"
    else
        Selection=("Downgrade device" "Disable/Enable exploit" "Restore to 7.1.2" "(Re-)Install Dependencies" "(Any other key to exit)")
        Echo "*** Main Menu ***"
        Input "Select an option:"
        select opt in "${Selection[@]}"; do
            case $opt in
                "Downgrade device" ) Mode='Downgrade'; break;;
                "Disable/Enable exploit" ) Mode='Remove4'; break;;
                "Restore to 7.1.2" ) Mode='Restore712'; break;;
                "(Re-)Install Dependencies" ) InstallDepends;;
                * ) exit 0;;
            esac
        done
    fi
    SelectVersion
}

SelectVersion() {
    Selection=("6.1.3" "5.1.1 (9B208)" "5.1.1 (9B206)" "More versions (5.0-6.1.2)" "4.3.x (not supported)" "7.x (not supported)")
    Selection2=("6.1.2" "6.1" "6.0.1" "6.0" "5.1" "5.0.1" "5.0")
    Selection3=("7.1.1" "7.1" "7.0.6" "7.0.4" "7.0.3" "7.0.2" "7.0")
    if [[ $Mode == 'Restore712' ]]; then
        Echo "* Make sure to disable the exploit first! See the README for more details."
        Input "Press Enter/Return to continue (or press Ctrl+C to cancel)"
        read -s
        OSVer='7.1.2'
        BuildVer='11D257'
    fi
    [[ $Mode != 'Downgrade' ]] && Action
    Input "Select iOS version:"
    select opt in "${Selection[@]}"; do
        case $opt in
            "6.1.3" ) OSVer='6.1.3'; BuildVer='10B329'; break;;
            "5.1.1 (9B208)" ) OSVer='5.1.1'; BuildVer='9B208'; break;;
            "5.1.1 (9B206)" ) OSVer='5.1.1'; BuildVer='9B206'; break;;
            "More versions (5.0-6.1.2)" ) OSVer='More'; break;;
            "4.3.x (not supported)" ) OSVer='4.3.x'; break;;
            "7.x (not supported)" ) OSVer='7.x'; break;;
            *) exit 0;;
        esac
    done
    if [[ $OSVer == 'More' ]]; then
        select opt in "${Selection2[@]}"; do
            case $opt in
                "6.1.2" ) OSVer='6.1.2'; BuildVer='10B146'; break;;
                "6.1" ) OSVer='6.1'; BuildVer='10B144'; break;;
                "6.0.1" ) OSVer='6.0.1'; BuildVer='10A523'; break;;
                "6.0" ) OSVer='6.0'; BuildVer='10A403'; break;;
                "5.1" ) OSVer='5.1'; BuildVer='9B176'; break;;
                "5.0.1" ) OSVer='5.0.1'; BuildVer='9A405'; break;;
                "5.0" ) OSVer='5.0'; BuildVer='9A334'; break;;
                *) exit 0;;
            esac
        done
    elif [[ $OSVer == '4.3.x' ]]; then
        Echo "* I can't verify if iOS 4.3.x works or not, let me know if it does work"
        select opt in "4.3.5" "4.3.3" "4.3"; do
            case $opt in
                "4.3.5" ) OSVer='4.3.5'; BuildVer='8L1'; break;;
                "4.3.3" ) OSVer='4.3.3'; BuildVer='8J2'; break;;
                "4.3" ) OSVer='4.3'; BuildVer='8F190'; break;;
                *) exit 0;;
            esac
        done
    elif [[ $OSVer == '7.x' ]]; then
        Echo "* I don't think any iOS 7.x version works (gets stuck in recovery mode)"
        select opt in "${Selection3[@]}"; do
            case $opt in
                "7.1.1" ) OSVer='7.1.1'; BuildVer='11D201'; break;;
                "7.1" ) OSVer='7.1'; BuildVer='11D169'; break;;
                "7.0.6" ) OSVer='7.0.6'; BuildVer='11B651'; break;;
                "7.0.4" ) OSVer='7.0.4'; BuildVer='11B554a'; break;;
                "7.0.3" ) OSVer='7.0.3'; BuildVer='11B511'; break;;
                "7.0.2" ) OSVer='7.0.2'; BuildVer='11A501'; break;;
                "7.0" ) OSVer='7.0'; BuildVer='11A465'; break;;
                *) exit 0;;
            esac
        done
    fi
    Action
}

Action() {
    Log "Option: $Mode"
    if [[ $Mode == 'Downgrade' || $Mode == 'Restore712' ]]; then
        read -p "$(Input 'Jailbreak the selected iOS version? (Y/n):')" Jailbreak
        [[ $Jailbreak != n && $Jailbreak != N ]] && Jailbreak=1
    fi

    [[ $Mode == 'Downgrade' || $Mode == 'Restore712' ]] && Downgrade
    [[ $Mode == 'Remove4' ]] && Remove4
    exit
}

SelectDFU() {
    Selection=("pwnedDFU" "ipwndfu")
    echo
    Input "Select pwnDFU tool to use (Select 1 if unsure, select 2 if 1 does not work):"
        select opt in "${Selection[@]}"; do
        case $opt in
            "ipwndfu" ) pwnedDFU=$ipwndfu; break;;
            *) break;;
        esac
    done
}

Recovery() {
    [[ $($irecovery -q 2>/dev/null | grep 'MODE' | cut -c 7-) == "Recovery" ]] && RecoveryDevice=1
    if [[ $RecoveryDevice != 1 ]]; then
        Log "Entering recovery mode..."
        $ideviceenterrecovery $UniqueDeviceID >/dev/null
        while [[ $RecoveryDevice != 1 ]]; do
            [[ $($irecovery -q 2>/dev/null | grep 'MODE' | cut -c 7-) == "Recovery" ]] && RecoveryDevice=1
        done
    fi
    Log "Device in recovery mode detected. Get ready to enter DFU mode"
    read -p "$(Input 'Select Y to continue, N to exit recovery (Y/n)')" RecoveryDFU
    if [[ $RecoveryDFU == n || $RecoveryDFU == N ]]; then
        Log "Exiting recovery mode."
        $irecovery -n
        exit 0
    fi
    Echo "* Hold TOP and HOME buttons for 10 seconds."
    for i in {10..01}; do
        echo -n "$i "
        sleep 1
    done
    echo -e "\n$(Echo '* Release TOP button and hold HOME button for 8 seconds.')"
    for i in {08..01}; do
        echo -n "$i "
        sleep 1
    done
    [[ $($irecovery -q 2>/dev/null | grep 'MODE' | cut -c 7-) == "DFU" ]] && DFUDevice=1
    if [[ $DFUDevice == 1 ]]; then
        EnterPwnDFU
    else
        Error "Failed to detect device in DFU mode. Please run the script again"
    fi
}

EnterPwnDFU() {
    SelectDFU
    echo -e "\n$(Log 'Entering pwnDFU mode...')"
    [[ $pwnedDFU == $ipwndfu ]] && cd resources/ipwndfu
    $pwnedDFU -p
    [[ $pwnedDFU == $ipwndfu ]] && cd ../..
    pwnDFUDevice=$($irecovery -q | grep -c 'PWND')
    [[ $pwnDFUDevice != 1 ]] && Error "Failed to enter pwnDFU mode. Please run the script again" "./restore.sh Downgrade"
}

Remove4() {
    Input "Select option:"
    select opt in "Disable exploit" "Enable exploit" "(Any other key to exit)"; do
        case $opt in
            "Disable exploit" ) Rec=0; break;;
            "Enable exploit" ) Rec=2; break;;
            * ) exit 0;;
        esac
    done
    if [[ ! -e saved/iBSS_8L1 ]]; then
        Log "Downloading iBSS..."
        $partialzip http://appldnld.apple.com/iPhone4/041-1966.20110721.V3Ufe/iPhone3,1_4.3.5_8L1_Restore.ipsw Firmware/dfu/iBSS.n90ap.RELEASE.dfu iBSS
        mkdir saved 2>/dev/null
        cp iBSS saved/iBSS_8L1
        mv iBSS tmp
    else
        cp saved/iBSS_8L1 tmp/iBSS
    fi
    Log "Patching iBSS..."
    $bspatch tmp/iBSS tmp/pwnediBSS resources/patches/iBSS.n90ap.8L1.patch
    SelectDFU
    Log "Booting iBSS..."
    if [[ $pwnedDFU == $ipwndfu ]]; then
        cd resources/ipwndfu
        $pwnedDFU -f ../../tmp/pwnediBSS
        cd ../..
    else
        $pwnedDFU -f tmp/pwnediBSS
    fi
    sleep 2
    Log "Running commands..."
    $irecovery -c "setenv boot-partition $Rec"
    $irecovery -c "saveenv"
    $irecovery -c "setenv auto-boot true"
    $irecovery -c "saveenv"
    $irecovery -c "reset"
    Log "Done!"
    Echo "* If disabling the exploit did not work and the device is getting stuck after restore:"
    Echo "* You may try another method for clearing NVRAM. See the README for more details"
}

iDeviceRestore() {
    Log "Extracting IPSW..."
    unzip -q $IPSW.ipsw -d $IPSW/
    Log "Proceeding to idevicerestore..."
    Echo "* Enter root password of your PC/Mac when prompted"
    [[ $platform == "macos" ]] && sudo codesign --sign - --force --deep $idevicerestore
    [[ $1 == "latest" ]] && ExtraArgs="-ey" || ExtraArgs="-ewy"
    $idevicerestore $ExtraArgs $IPSW.ipsw
    if [[ $platform == "macos" && $? != 0 ]]; then
        Log "An error seems to have occurred when running idevicerestore."
        Echo "* If this is the \"Killed: 9\" error or similar, try these steps:"
        Echo "* Using Terminal, cd to where the script is located, then run"
        Echo "* sudo codesign --sign - --force --deep resources/tools/idevicerestore_macos"
    fi
    Log "Restoring done!"
    Log "Downgrade script done!"
}

Downgrade() {
    [[ $Jailbreak == 1 ]] && Custom="Custom" || Custom="CustomW"
    IPSW="iPhone3,1_${OSVer}_${BuildVer}_Restore"
    IPSWCustom="iPhone3,1_${OSVer}_${BuildVer}_${Custom}"
    IPSW7="iPhone3,1_7.1.2_11D257_Restore"
    if [[ ! -e $IPSWCustom.ipsw ]]; then
        [[ ! -e $IPSW.ipsw ]] && Error "iOS $OSVer-$BuildVer IPSW cannot be found."
        [[ ! -e $IPSW7.ipsw ]] && Error "iOS 7.1.2 IPSW cannot be found."
    fi

    if [[ $OSVer == 7.1.1 ]]; then
        IV=b110991061d76f74c1fc05ddd7cff540
        Key=c6fbf428e0105ab22b2abaefd20ca22c2084e200f74e8a3b08298a54f8bfe28f
    elif [[ $OSVer == 7.1 ]]; then
        IV=9fe5b6785126c8fc5787582df9efcf94
        Key=b68612f21e377bd1f685e9031be159a724e931eff162db245c63b7b692cefa7e
    elif [[ $OSVer == 7.0.6 ]]; then
        IV=12af3a975f0346e89d3a34e73b4e0ae1
        Key=d7b5bb9b90f19493449ab17fda63afdb16069ad5b65026bb11b4db223fdd4be1
    elif [[ $OSVer == 7.0.4 ]]; then
        IV=67087ac7f28c77cdf9110356f476540b
        Key=2a6940252b5cb19b86efb9005cdd5fd713290e573dc760f5a3e05df9e868bb89
    elif [[ $OSVer == 7.0.3 ]]; then
        IV=7cb97df787dcc6367816b03492b225f9
        Key=bd56f0886e21f233f519d4db20fd044b9208882a6fb791553a75eb4e0c45bbc5
    elif [[ $OSVer == 7.0.2 ]]; then
        IV=65db9a4e4f64bb79a55d76d98ce1457b
        Key=5cd910c268813cb4008e5b33e01f761c0794ed1437737b4d386727d17fac79d1
    elif [[ $OSVer == 7.0 ]]; then
        IV=5bf099d9db5cf1009329e527a378c8be
        Key=e1fef31c8aabcdca2a3887ba21c0e2113c41a5617380657ab6a487993b39f9a8
    elif [[ $OSVer == 6.1.3 ]]; then
        IV=b559a2c7dae9b95643c6610b4cf26dbd
        Key=3dbe8be17af793b043eed7af865f0b843936659550ad692db96865c00171959f
    elif [[ $OSVer == 6.1.2 ]]; then
        IV=c939629e3473fdb67deae0c45582506d
        Key=cbcd007712618cb6ab3be147f0317e22e7cceadb344e99ea1a076ef235c2c534
    elif [[ $OSVer == 6.1 ]]; then
        IV=4d76b7e25893839cfca478b44ddef3dd
        Key=891ed50315763dac51434daeb8543b5975a555fb8388cc578d0f421f833da04d
    elif [[ $OSVer == 6.0.1 ]]; then
        IV=44ffe675d6f31167369787a17725d06c
        Key=8d539232c0e906a9f60caa462f189530f745c4abd81a742b4d1ec1cb8b9ca6c3
    elif [[ $OSVer == 6.0 ]]; then
        IV=7891928b9dd0dd919778743a2c8ec6b3
        Key=838270f668a05a60ff352d8549c06d2f21c3e4f7617c72a78d82c92a3ad3a045
    elif [[ $BuildVer == 9B206 ]]; then
        IV=b1846de299191186ce3bbb22432eca12
        Key=e8e26976984e83f967b16bdb3a65a3ec45003cdf2aaf8d541104c26797484138
    elif [[ $BuildVer == 9B208 ]]; then
        IV=71fe96da25812ff341181ba43546ea4f
        Key=6377d34deddf26c9b464f927f18b222be75f1b5547e537742e7dfca305660fea
    elif [[ $OSVer == 5.1 ]]; then
        IV=b1846de299191186ce3bbb22432eca12
        Key=e8e26976984e83f967b16bdb3a65a3ec45003cdf2aaf8d541104c26797484138
    elif [[ $OSVer == 5.0.1 ]]; then
        IV=49eb54980a0024f91b079faf0ee87f67
        Key=c3a49f0059075e1453dacec4c3e4d89bd7a433ee19c8d48e4695d89b4c84a373
    elif [[ $OSVer == 5.0 ]]; then
        IV=15dd404efbb24a842d08dcde21e777a0
        Key=71614af73814c3a8e6724d592ecfccdbace766dad5eb39b0b8313387e94d2964
    elif [[ $OSVer == 4.3.5 ]]; then
        IV=986032eecd861c37ca2a86b6496a3c0d
        Key=b4e300c54a9dd2e648ead50794e9bf2205a489c310a1c70a9fae687368229468
        ios4="-ios4"
    elif [[ $OSVer == 4.3.3 ]]; then
        IV=bb3fc29dd226fac56086790060d5c744
        Key=c2ead1d3b228a05b665c91b4b1ab54b570a81dffaf06eaf1736767bcb86e50de
        ios4="-ios433"
    elif [[ $OSVer == 4.3 ]]; then
        IV=9f11c07bde79bdac4abb3f9707c4b13c
        Key=0958d70e1a292483d4e32ed1e911d2b16b6260856be67d00a33b6a1801711d32
        ios4="-ios433"
    fi

    if [[ $Jailbreak == 1 ]]; then
        if [[ $OSVer == 7.1* ]]; then
            JBFiles=(Cydia7.tar panguaxe.tar fstab7.tar)
            JBSHA1=bba5022d6749097f47da48b7bdeaa3dc67cbf2c4
        elif [[ $OSVer == 7.* ]]; then
            JBFiles=(Cydia7.tar evasi0n7-untether.tar fstab7.tar)
            JBSHA1=bba5022d6749097f47da48b7bdeaa3dc67cbf2c4
        elif [[ $OSVer == 6.1.3 ]]; then
            JBFiles=(Cydia6.tar p0sixspwn.tar)
            JBSHA1=1d5a351016d2546aa9558bc86ce39186054dc281
        elif [[ $OSVer == 6.* ]]; then
            JBFiles=(Cydia6.tar evasi0n6-untether.tar)
            JBSHA1=1d5a351016d2546aa9558bc86ce39186054dc281
        elif [[ $OSVer == 5.* || $OSVer == 4.3* ]]; then
            JBFiles=(Cydia5.tar unthredeh4il.tar)
            JBSHA1=f5b5565640f7e31289919c303efe44741e28543a
        fi
        [[ $OSVer != 7.* ]] && JBFiles+=(fstab_rw.tar)
        if [[ ! -e resources/jailbreak/${JBFiles[0]} ]]; then
            Log "Downloaading jailbreak files..."
            cd tmp
            SaveFile https://github.com/LukeZGD/iOS-OTA-Downgrader-Keys/releases/download/jailbreak/${JBFiles[0]} ${JBFiles[0]} $JBSHA1
            cp ${JBFiles[0]} ../resources/jailbreak
            cd ..
        fi
        for i in {0..2}; do
            JBFiles[$i]=resources/jailbreak/${JBFiles[$i]}
        done
    fi

    if [[ ! -e saved/shsh/blobs712_${UniqueChipID}.shsh ]]; then
        Log "Saving 7.1.2 blobs with tsschecker..."
        $tsschecker -d $ProductType -i 7.1.2 -e $UniqueChipID -m resources/BuildManifest.plist -s
        SHSH=$(ls ${UniqueChipID}_${ProductType}_7.1.2-11D257_*.shsh2)
        [[ ! $SHSH ]] && Error "Saving $OSVer blobs failed. Please run the script again"
        mkdir saved/shsh 2>/dev/null
        cp $SHSH saved/shsh/blobs712_${UniqueChipID}.shsh
        Log "Successfully saved 7.1.2 blobs."
    else
        cp saved/shsh/blobs712_${UniqueChipID}.shsh .
        SHSH="blobs712_${UniqueChipID}.shsh"
    fi
    mkdir shsh
    mv $SHSH shsh/${UniqueChipID}-${ProductType}-${OSVer}.shsh

    [[ $OSVer == 4.3* ]] && IPSWCustom=$IPSWCustom-$UniqueChipID
    if [[ $Mode == 'Restore712' && $Jailbreak != 1 ]]; then
        iDeviceRestore latest
        exit
    elif [[ $Mode == 'Restore712' && ! -e $IPSWCustom.ipsw ]]; then
        Echo "* By default, memory option is set to Y."
        Echo "* Make sure that you have at least 8GB of RAM for it to work!"
        Echo "* If it freezes or fails, this may mean that you do not have enough RAM."
        Echo "* You may select N if this happens, but make sure that you have enough storage space."
        read -p "$(Input 'Memory option? (press Enter/Return if unsure) (Y/n):')" JBMemory
        [[ $JBMemory != n && $JBMemory != N ]] && JBMemory="-memory" || JBMemory=
        Log "Preparing custom IPSW..."
        cp -rf resources/FirmwareBundles FirmwareBundles
        $ipsw $IPSW.ipsw $IPSWCustom.ipsw $JBMemory -S 50 ${JBFiles[@]}
    elif [[ ! -e $IPSWCustom.ipsw ]]; then
        Echo "* By default, memory option is set to Y."
        Echo "* Make sure that you have at least 8GB of RAM for it to work!"
        Echo "* If it freezes or fails, this may mean that you do not have enough RAM."
        Echo "* You may select N if this happens, but make sure that you have enough storage space."
        read -p "$(Input 'Memory option? (press Enter/Return if unsure) (Y/n):')" JBMemory
        [[ $JBMemory != n && $JBMemory != N ]] && JBMemory="-memory" || JBMemory=
        Log "Preparing custom IPSW with ch3rryflower..."
        sed -z -i "s|\n../bin|\n../$cherry/bin|g" $cherry/make_iBoot.sh
        $cherry/make_iBoot.sh $IPSW.ipsw -iv $IV -k $Key $ios4
        cp -rf $cherrymac/FirmwareBundles FirmwareBundles
        cp -rf $cherrymac/src src
        $cherry/cherry $IPSW.ipsw $IPSWCustom.ipsw $JBMemory -derebusantiquis $IPSW7.ipsw iBoot ${JBFiles[@]}
        [[ $OSVer == 4.3* ]] && iOS4Fix
    fi
    [[ ! -e $IPSWCustom.ipsw ]] && Error "Failed to find custom IPSW. Please run the script again" "You may try selecting N for memory option"
    IPSW=$IPSWCustom

    iDeviceRestore
}

iOS4Fix() {
    Log "iOS 4 Fix" # From ios4fix
    cp shsh/$UniqueChipID-iPhone3,1-$OSVer.shsh tmp/apticket.plist
    zip -d $IPSWCustom.ipsw Firmware/all_flash/all_flash.n90ap.production/manifest
    cd src/n90ap/Firmware/all_flash/all_flash.n90ap.production
    unzip -j ../../../../../$IPSW.ipsw Firmware/all_flash/all_flash*/applelogo*
    mv -v applelogo-640x960.s5l8930x.img3 applelogo4-640x960.s5l8930x.img3
    echo "0000010: 34" | xxd -r - applelogo4-640x960.s5l8930x.img3
    echo "0000020: 34" | xxd -r - applelogo4-640x960.s5l8930x.img3
    if [[ $platform == macos ]]; then
        plutil -extract 'APTicket' xml1 ../../../../../shsh/$UniqueChipID-iPhone3,1-$OSVer.plist -o 'apticket.plist'
    else
        echo '<?xml version="1.0" encoding="UTF-8"?>' > apticket.plist
        echo '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' >> apticket.plist
        printf '<plist version="1.0">\n<data>' >> apticket.plist
        xmlstarlet sel -t -m "/plist/dict/key[.='APTicket']" -v "following-sibling::data[1]" ../../../../../tmp/apticket.plist >> apticket.plist
        echo -e '</data>\n</plist>' >> apticket.plist
        sed -i -e 's/[ \t]*//' apticket.plist
    fi
    cat apticket.plist | sed -ne '/<data>/,/<\/data>/p' | sed -e "s/<data>//" | sed "s/<\/data>//" | awk '{printf "%s",$0}' | base64 --decode > apticket.der
    ../../../../../$cherry/bin/xpwntool apticket.der applelogoT-640x960.s5l8930x.img3 -t scab_template.img3
    cd ../../..
    zip -r0 ../../$IPSWCustom.ipsw Firmware/all_flash/all_flash.n90ap.production/manifest
    zip -r0 ../../$IPSWCustom.ipsw Firmware/all_flash/all_flash.n90ap.production/applelogo4-640x960.s5l8930x.img3
    zip -r0 ../../$IPSWCustom.ipsw Firmware/all_flash/all_flash.n90ap.production/applelogoT-640x960.s5l8930x.img3
    cd ../..
}

InstallDepends() {
    mkdir tmp 2>/dev/null
    cd resources
    rm -rf lib/* libimobiledevice* libirecovery
    cd ../tmp

    Log "Installing dependencies..."
    if [[ $platform == "linux" ]]; then
        Echo "* iPhone4Down will be installing dependencies from your distribution's package manager"
        Echo "* Enter root password of your PC when prompted"
        Input "Press Enter/Return to continue (or press Ctrl+C to cancel)"
        read -s
    fi
    if [[ $ID == "arch" || $ID_LIKE == "arch" || $ID == "artix" ]]; then
        sudo pacman -Sy --noconfirm --needed base-devel bsdiff curl expect libimobiledevice libusbmuxd libzip python2 unzip usbmuxd usbutils vim xmlstarlet

    elif [[ -n $UBUNTU_CODENAME && $VERSION_ID == "2"* ]] ||
         [[ $VERSION == "11 (bullseye)" || $PRETTY_NAME == "Debian"*"sid" ]]; then
        [[ -n $UBUNTU_CODENAME ]] && sudo add-apt-repository -y universe
        sudo apt update
        sudo apt install -y bsdiff curl expect git libimobiledevice6 python2 unzip usbmuxd usbutils xmlstarlet xxd

    elif [[ $ID == "fedora" ]] && (( $VERSION_ID <= 33 )); then
        sudo dnf install -y bsdiff expect git libimobiledevice perl-Digest-SHA python2 vim-common xmlstarlet

    elif [[ $ID == "opensuse-tumbleweed" || $PRETTY_NAME == "openSUSE Leap 15.3" ]]; then
        if [[ $ID == "opensuse-tumbleweed" ]]; then
            libimobiledevice="libimobiledevice-1_0-6"
        else
            libimobiledevice="libimobiledevice6"
            ln -sf /lib64/libreadline.so.7 ../resources/lib/libreadline.so.8
        fi
        sudo zypper -n in bsdiff curl expect git $libimobiledevice libzip5 python-base vim xmlstarlet

    elif [[ $OSTYPE == "darwin"* ]]; then
        xcode-select --install
        libimobiledevice=("https://github.com/libimobiledevice-win32/imobiledevice-net/releases/download/v1.3.14/libimobiledevice.1.2.1-r1116-osx-x64.zip" "328e809dea350ae68fb644225bbf8469c0f0634b")

    else
        Error "Distro not detected/supported by the install script." "See the repo README for supported OS versions/distros"
    fi

    if [[ $platform == "linux" ]]; then
        libimobiledevice=("https://github.com/LukeZGD/iOS-OTA-Downgrader-Keys/releases/download/tools/libimobiledevice_linux.zip" "95e2ffc86b35c71039fcf3ef732e30dd766112ce")
    fi

    if [[ ! -d ../resources/libimobiledevice_$platform ]]; then
        SaveFile ${libimobiledevice[0]} libimobiledevice.zip ${libimobiledevice[1]}
        mkdir ../resources/libimobiledevice_$platform
        unzip libimobiledevice.zip -d ../resources/libimobiledevice_$platform
        chmod +x ../resources/libimobiledevice_$platform/*
    fi

    if [[ $platform == "macos" ]]; then
        Echo "* macOS device detected. For macOS, it is recommended to use cherryflowerJB instead as this script is mostly aimed for Linux users"
        Echo "* If you still want to use this, you need to have Homebrew installed, and install libpng using 'brew install libpng'"
        Echo "* There may be other dependencies needed but I haven't tested it"
    fi

    Log "Install script done! Please run the script again to proceed"
    exit 0
}

SaveExternal() {
    local ExternalURL="https://github.com/LukeZGD/$1.git"
    local External=$1
    cd resources
    if [[ ! -d $External || ! -d $External/.git ]]; then
        Log "Downloading $External..."
        rm -rf $External
        $git clone $ExternalURL $External
    fi
    if [[ ! -e $External/README.md || ! -d $External/.git ]]; then
        rm -rf $External
        Error "Downloading/updating $1 failed. Please run the script again"
    fi
    if [[ $External == ipwndfu ]]; then
        cd ipwndfu
        git checkout old &>/dev/null
        git reset --hard &>/dev/null
        cd ..
    fi
    cd ..
}

SaveFile() {
    curl -L $1 -o $2
    if [[ $(shasum $2 | awk '{print $1}') != $3 ]]; then
        Error "Verifying failed. Please run the script again" "./restore.sh Install"
    fi
}

cd "$(dirname $0)"
Main $1
