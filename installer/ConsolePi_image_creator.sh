#!/usr/bin/env bash

# --                                               ConsolePi Image Creation Script - Use at own Risk
# --  Wade Wells - Updated Aug 2019
# --    !!! USE @ own risk - This could bork your system !!!
# --
# --  This is a script I used to expedite testing.  It looks for a raspbian-lite image file in whatever directory you run the script from, if it doesn't find one
# --  it downloads the latest image.  It will guesses what drive is the micro-sd card (looks for usb to micro-sd adapter then sd to micro-sd) then flashes
# --  the raspbian-lite image to the micro-sd.
# --
# --  This script is an optional tool, provided just because I had it/used it for testing.  It simply automates the burning of the image to the sd-card and provides
# --    a mechanism to pre-configure a number of items and place whatever additional files you might want on the image.
# --
# --  You do get the opportunity to review fdisk -l to ensure it's the correct drive, and you can override the drive the script selects.  Obviously if you
# --  were to select the wrong drive, you would wipe out anything on that drive.  So don't do that.  I did add a validation check which detect if the drive contains
# --  a partition with the boot flag in fdisk
# --
# --  To further expedite testing this script will look for a ConsolePi_stage subdir and if found it will copy the entire directory and any subdirs to /home/pi/ConsolePi_stage
# --  This script also searches the script dir (the dir this script is ran from) for the following which are copied to the /home/pi directory on the ConsolePi image if found.
# --    ConsolePi.conf, ConsolePi.ovpn, ovpn_credentials *.dtbo
# --
# --    The install script (not this one this is the image creator) looks for these files in the home dir of whatever user your logged in with and in 'ConsolePi_stage' subdir.
# --      If found it will pull them in.  If the installer finds ConsolePi.conf it uses those values as the defaults allowing you to bypass the data entry (after confirmation).
# --    The OpenVPN related files are moved (by the installer) to the openvpn/client folder.
# --      The installer only provides example ovpn files as the specifics would be dependent on how your openvpn server is configured
# --
# --  To aid in headless installation this script will enable SSH and can configure a wlan_ssid.  With those options on first boot the raspberry pi will connect to
# --  the SSID, so all you need to do is determine the IP address assigned and initiate an SSH session.
# --    To enable the pre-configuration of an SSID, either configure the parameters below with values appropriate for your system *or* provide a valid wpa_supplicant.conf
# --    file in either the script dir or ConsolePi_stage subdir.  EAP-TLS can also be pre-configured, just define it in wpa_supplicant.conf and provide the certs
# --    referenced in the wpa_supplicant.conf in the script dir a 'cert' subdir or 'ConsolePi_stage/cert' subdir.
# --    This script will copy wpa_supplicant.conf and any certs if defined and found to the appropriate dirs so ConsolePi can use those settings on first boot.
# --
# --  The install script (again not this script) also handles a few other files, they just need to be provided in the ConsolePi_stage subdir
# --    This includes:
# --      - 10-ConsolePi.rules: udev rules file mapping specific serial adapters to specific telnet ports
# --      - ConsolePi_init.sh: Custom post-install script, the installer will run this script at the end of the process, it can be used to automate any additional tweaks
# --          you might want to make.  i.e. copy additional custom scripts you like to have on hand from the ConsolePi_stage dir to wherever you want them.
# --      - authorized_keys: imported for both pi and root user (for now)
# --      - rpi-poe-overlay.dts: Used to adjust thresholds for when and how fast the fan will kick on (PoE hat). Install script will create the dtbo overlay based on this dts.
# --
# --  Lastly this script also configures one of the consolepi quick commands: 'consolepi-install'. This command
# --  is the same as the single command install command on the github.  btw the 'consolepi-install' command is changed to 'consolepi-upgrade' during the install.
# --
# --  This script should be ran on a Linux system, tested on raspbian (a different Raspberry pi), and Linux mint, should work on most Linux distros certailny Debain/Ubuntu based
# --  To use this script enter command:
# --    'curl -JLO https://raw.githubusercontent.com/Pack3tL0ss/ConsolePi/master/installer/ConsolePi_image_creator.sh  && sudo chmod +x ConsolePi_image_creator.sh'
# --  Enter a micro-sd card using a usb to micro-sd card adapter (script only works with usb to micro-sd adapters)
# --  'sudo ./ConsolePi_image_creator.sh' When you are ready to flash the image

# -------------------- // CONFIGURATION \\ --------------------
# -- WLAN (device will boot and look for the SSID) --
configure_wpa_supplicant=false  # nothing is applied if this is false
ssid='ExampleSSID'
psk='ChangeMe!!'
wlan_country="US"
priority=0

# -- image selection --
#   valid options are:
#     'lite': Minimal image, no desktop environment
#     'desktop': Image with desktop environment
#     'full': Image with desktop and recommended software
img_type='lite'

local_dev=false

# if img_only=true only burn the image and enable SSH (I run headless), no other pre-staging is done. This is for testing more commom install scenario
img_only=false

# -- Auto Launch ConsolePi installer when user logs in --
auto_install=true

# Terminal coloring
_norm='\e[0m'
_bold='\033[1;32m'
_blink='\e[5m'
_red='\e[31m'
_blue='\e[34m'
_lred='\e[91m'
_yellow='\e[33;1m'
_green='\e[32m'
_cyan='\e[96m' # technically light cyan

header() {
    [ "$1" == 'clear' ] && clear
    echo -e "${_cyan}   ______                       __    ${_lred} ____  _ "
    echo -e "${_cyan}  / ____/___  ____  _________  / /__  ${_lred}/ __ \(_)"
    echo -e "${_cyan} / /   / __ \/ __ \/ ___/ __ \/ / _ \\\\${_lred}/ /_/ / / "
    echo -e "${_cyan}/ /___/ /_/ / / / (__  ) /_/ / /  __${_lred}/ ____/ /  "
    echo -e "${_cyan}\____/\____/_/ /_/____/\____/_/\___${_lred}/_/   /_/   "
    echo -e "${_blue}  https://github.com/Pack3tL0ss/ConsolePi${_norm}"
    echo -e ""
}

green() {
    echo -e "\033[1;32m${*}\033[m"
}

cyan() {
    echo -e "\e[96m${*}\033[m"
}

# Function to collect user input
get_input() {
    valid_input=false
    while ! $valid_input; do
    read -ep "${prompt} (y/n|exit): " input
    case ${input,,} in
        'y'|'yes')
        input=true
        valid_input=true
        ;;
        'n'|'no')
        input=false
        valid_input=true
        ;;
        'exit')
        echo 'Exiting Script based on user input'
        exit 1
        ;;
        *)
        valid_input=false
        echo -e '\n\n!!! Invalid Input !!!\n\n'
        ;;
    esac
    done
    prompt=
}

do_unzip() {
    echo "Extracting image from ${1}"
    unzip $1
    img_file=$(ls -lc "${1%zip}img" 2>>/dev/null | awk '{print $9}')
    [[ -z $img_file ]] && echo 'Something went wrong img file not found after unzip... exiting' && exit 1
}

show_disk_details() {
echo -e "------------------------------- // Device Details for $(green "$my_usb") \\\\\ -----------------------------------"
echo
fdisk -l | sed -n "/Disk \/dev\/${my_usb}:/,/Disk \/${my_usb}\//p"
echo
echo -e "--------------------------------------------------------------------------------------------"
}

# -- Check for ConsolePi.yaml collect info if not found --
do_import_configs() {
    # Look for pre-configuration files in script dir.  Also if ConsolePi_stage subdir is found in script dir cp the dir to the ConsolePi image
    cur_dir=$(pwd)
    pi_home="/mnt/usb2/home/pi"
    [[ -f ConsolePi.conf ]] && cp ConsolePi.conf $pi_home  && echo " + ConsolePi.conf found pre-staging on image"
    [[ -f ConsolePi.ovpn ]] && cp ConsolePi.ovpn $pi_home && echo " + ConsolePi.ovpn found pre-staging on image"
    [[ -f ovpn_credentials ]] && cp ovpn_credentials $pi_home && echo " + ovpn_credentials found pre-staging on image"
    [[ -f ConsolePi_init.sh ]] && cp ConsolePi_init.sh $pi_home && echo " + Custome Post install script found pre-staging on image"
    [[ -d ConsolePi_stage ]] && sudo -u pi mkdir $pi_home/ConsolePi_stage &&
        sudo cp -r ${cur_dir}/ConsolePi_stage/* $pi_home/ConsolePi_stage/ && echo " + ConsolePi_stage dir found Pre-Staging all files"
    [[ -f $pi_home/ConsolePi_stage/authorized_keys ]] && echo " + .ssh authorized keys found pre-staging" &&
        sudo -u pi mkdir -p $pi_home/.ssh
        sudo mkdir -p /mnt/usb2/root/.ssh
        sudo -u pi cp ${cur_dir}/ConsolePi_stage/authorized_keys $pi_home/.ssh/
        sudo cp ${cur_dir}/ConsolePi_stage/authorized_keys /mnt/usb2/root/.ssh/
    [[ -f $pi_home/ConsolePi_stage/known_hosts ]] && echo " + .ssh known_hosts found pre-staging" &&
        sudo -u pi cp ${cur_dir}/ConsolePi_stage/known_hosts $pi_home/.ssh/
        chown -R pi:pi $pi_home/.ssh/
        sudo cp ${cur_dir}/ConsolePi_stage/known_hosts /mnt/usb2/root/.ssh/

    # if wpa_supplicant.conf exist in script dir cp it to ConsolePi image.
    # if EAP-TLS SSID is configured in wpa_supplicant extract EAP-TLS cert details and cp certs (not a loop only good to pre-configure 1)
    #   certs should be in script dir or 'cert' subdir cert_names are extracted from the wpa_supplicant.conf file found in script dir
    [[ -f wpa_supplicant.conf ]] && found_path="${cur_dir}/wpa_supplicant.conf" || found_path=
    [[ -d ConsolePi_stage ]] && [[ -f ConsolePi_stage/wpa_supplicant.conf ]] && found_path="${cur_dir}/ConsolePi_stage/wpa_supplicant.conf" || found_path=
    if [[ $found_path ]]; then
        echo " + wpa_supplicant.conf found pre-staging on image"
        sudo cp $found_path /mnt/usb2/etc/wpa_supplicant
        sudo chown root /mnt/usb2/etc/wpa_supplicant/wpa_supplicant.conf
        sudo chgrp root /mnt/usb2/etc/wpa_supplicant/wpa_supplicant.conf
        sudo chmod 644 /mnt/usb2/etc/wpa_supplicant/wpa_supplicant.conf
        client_cert=$(grep client_cert= $found_path | cut -d'"' -f2| cut -d'"' -f1)
        if [[ ! -z $client_cert ]]; then
            cert_path="/mnt/usb2"${client_cert%/*}
            ca_cert=$(grep ca_cert= $found_path | cut -d'"' -f2| cut -d'"' -f1)
            private_key=$(grep private_key= $found_path | cut -d'"' -f2| cut -d'"' -f1)
            if [[ -d cert/ ]]; then
                cd cert
            elif [[ -d ConsolePi_stage/cert/ ]]; then
                cd ConsolePi_stage/cert/
            fi
            [[ ! -d $cert_path ]] && sudo mkdir -p $cert_path
            [[ -f ${client_cert##*/} ]] && sudo cp ${client_cert##*/} "${cert_path}/${client_cert##*/}"
            [[ -f ${ca_cert##*/} ]] && sudo cp ${ca_cert##*/} "${cert_path}/${ca_cert##*/}"
            [[ -f ${private_key##*/} ]] && sudo cp ${private_key##*/} "${cert_path}/${private_key##*/}"
            cd $cur_dir
        fi
    fi

    if ! [ -f $cur_dir/ConsolePi_stage/ConsolePi.yaml ]; then
        if [ -f /etc/ConsolePi/ConsolePi.yaml ]; then
            prompt="Do you want to pre-stage configuration using the config from this ConsolePi" && get_input
            if $input; then
                sudo -u $SUDO_USER mkdir -p $pi_home/ConsolePi_stage
                sudo -u $SUDO_USER cp /etc/ConsolePi/ConsolePi.yaml $pi_home/ConsolePi_stage/
            fi
        fi
    fi

    if [ -f $pi_home/ConsolePi_stage/ConsolePi.yaml ]; then
        prompt="Do you want to edit the pre-staged ConsolePi.yaml to change details" && get_input
        $input && nano $pi_home/ConsolePi_stage/ConsolePi.yaml
        cfg_ssid=$(grep '  wlan_ssid: ' $pi_home/ConsolePi_stage/ConsolePi.yaml | awk '{print $2}')
        [[ ! -z $cfg_ssid ]] && prompt="Do you want to pre-stage the hostname as $cfg_ssid" && get_input
        $input && echo $cfg_ssid > /mnt/usb2/etc/hostname
    fi
}


main() {
    if ! $configure_wpa_supplicant && [[ ! -f "$(pwd)/wpa_supplicant.conf" ]] && [[ ! -f "$(pwd)/ConsolePi_stage/wpa_supplicant.conf" ]]; then
        echo "wlan configuration will not be applied to image, to apply WLAN configuration break out of the script & change params @"
        echo "top of this script *or* provide wpa_supplicant.conf in script directory."
    fi

    my_usb=$(ls -l /dev/disk/by-path/*usb* 2>/dev/null |grep -v part | sed 's/.*\(...\)/\1/')
    [[ $my_usb ]] && boot_list=($(sudo fdisk -l |grep -o '/dev/sd[a-z][0-9]  \*'| cut -d'/' -f3| awk '{print $1}'))
    [[ $boot_list =~ $my_usb ]] && my_usb=    # if usb device found make sure it's not marked as bootable if so reset my_usb so we can check for sd card adapter
    [[ -z $my_usb ]] && my_usb=$( sudo fdisk -l | grep 'Disk /dev/mmcblk' | awk '{print $2}' | cut -d: -f1 | cut -d'/' -f3)

    header "clear"

    echo -e "\n\n$(green "ConsolePi Image Creator") \n'exit' (which will terminate the script) is valid at all prompts\n"
    [[ $my_usb ]] && echo -e "Script has discovered removable flash device @ $(green "${my_usb}") with the following details\n" ||
        echo -e "Script failed to detect removable flash device, you will need to specify the device"

    show_disk_details ${my_usb}

    # Give user chance to change target drive
    echo -e "\n\nPress enter to accept $(green "${my_usb}") as the destination drive or specify the correct device (i.e. 'sdc' or 'mmcblk0')"

    read -ep "Device to flash with image [$(green "${my_usb}")]: " drive
    [[ ${drive,,} == "exit" ]] && echo "Exit based on user input." && exit 1

    if [[ $drive ]]; then
        if [[ $boot_list =~ $drive ]]; then
            prompt="The selected drive contains a bootable partition, are you sure about this?" && get_input
            ! $input && echo "Exiting based on user input" && exit 1
        fi
        drive_list=( $(sudo fdisk -l | grep 'Disk /dev/' | awk '{print $2}' | cut -d'/' -f3 | cut -d':' -f1) )
        [[ $drive_list =~ $drive ]] && echo "${my_usb} not found on system. Exiting..." && exit 1
        my_usb=$drive
    fi

    [[ -z $my_usb ]] && echo "Something went wrong no destination device selected... exiting" && exit 1

    # umount device if currently mounted
    go_umount=true
    while $go_umount; do
        mount_point=$(mount | tail -1 | grep "${my_usb}" | awk '{print $3}')
        [[ ! -z $mount_point ]] && sudo umount $mount_point && echo "un-mounting $mount_point" || go_umount=false
    done

    # get raspbian-lite image if not in script dir
    echo -e "\nGetting latest raspbian image (${img_type})"

    # Find out what current raspbian release is
    [ ! $img_type = 'desktop' ] && img_url="https://downloads.raspberrypi.org/raspbian_${img_type}_latest" ||
        img_url="https://downloads.raspberrypi.org/raspbian_latest"

    # remove DH cipher security improvement in curl broke this, need this until raspberrypi.org changes to use a larger key
    cur_rel=$(curl -sIL --ciphers 'DEFAULT:!DH' $img_url | \
        grep -o -E "[0-9]{4}-[0-9]{2}-[0-9]{2}-raspbian-[a-z,A-Z]*.{1}[a-z]*.zip" | head -1 | cut -d'.' -f1)

    # Check to see if any images exist in script dir already
    found_img_file=$(ls -lc *raspbian*.img 2>>/dev/null | awk '{print $9}')
    found_img_zip=$(ls -lc *raspbian*.zip 2>>/dev/null | awk '{print $9}')
    readarray -t found_img_files <<<"$found_img_file"
    readarray -t found_img_zips <<<"$found_img_zip"

    # If img or zip raspbian-lite image exists in script dir see if it is current
    # if not prompt user to determine if they want to download current
    if [[ $found_img_file ]]; then
        if [[ ! " ${found_img_files[@]} " =~ " ${cur_rel}.img " ]]; then
            echo "the following images were found:"
            idx=1
            for i in ${found_img_files[@]}; do echo ${idx}. ${i} && ((idx=$idx+1));  done
            echo -e "\nbut the current release is $(cyan $cur_rel)"
            prompt="Would you like to download and use the latest release? ($(cyan $cur_rel)):"
            get_input
            $input || img_file=$found_img_file # selecting no won't likely won't work right now
        else
            echo "Using image $(cyan ${cur_rel%.img}), found in $(pwd). It is the current release"
            img_file=${cur_rel}.img
        fi
    elif [[ $found_img_zip ]]; then
        if [[ ! " ${found_img_zips[@]} " =~ " ${cur_rel}.zip " ]]; then
            echo "the following images were found:"
            idx = 1
            for i in ${found_img_zips[@]}; do echo ${idx}. ${i} && ((idx=$idx+1));  done
            echo -e "\nbut the current release is $(cyan $cur_rel)"
            prompt="Would you like to download and use the latest release? ($(cyan ${cur_rel})):"
            get_input
            $input || do_unzip $found_img_zip ## selecting no won't likely won't work right now # img_file assigned in do_unzip
        else
            echo "Using $(cyan ${cur_rel}) found in $(pwd). It is the current release"
            do_unzip ${cur_rel}.zip #img_file assigned in do_unzip
        fi
    else
        echo "no image found in $(pwd)"
    fi

    # img_file will only be assigned if an image was found in the script dir
    retry=1
    while [[ -z $img_file ]] ; do
        [[ $retry > 3 ]] && echo "Exceeded retries exiting " && exit 1
        echo "downloading image from raspberrypi.org.  Attempt: ${retry}"
        # curl -JLO https://downloads.raspberrypi.org/raspbian_lite_latest
        wget -q $img_url -O ${cur_rel}.zip
        do_unzip "${cur_rel}.zip"
        ((retry++))
    done

    # ----------------------------------- // Burn Raspian image to device (micro-sd) \\ -----------------------------------
    echo -e "\n\n${_red}!!! Last chance to abort !!!${_norm}"
    prompt="About to burn $(cyan ${img_file}) to $(green ${my_usb}), Continue?"
    get_input
    ! $input && echo 'Exiting Script based on user input' && exit 1
    header "clear"
    echo -e "\nNow Burning image $(cyan ${img_file}) to $(green ${my_usb}) standby...\n this takes a few minutes\n"
    sudo dd bs=4M if="${img_file}" of=/dev/${my_usb} conv=fsync status=progress &&
        echo -e "\n\n\033[1;32mImage written to flash - no Errors\033[m\n\n" ||
        ( echo -e "\n\n\033[1;32mError occurred burning image\033[m\n\n" && exit 1 )

    # Create some mount-points if they don't exist already.  Script will remove them if it has to create them, they will remain if they were already there
    [[ ! -d /mnt/usb1 ]] && sudo mkdir /mnt/usb1 && usb1_existed=false || usb1_existed=true
    [[ ! -d /mnt/usb2 ]] && sudo mkdir /mnt/usb2 && usb2_existed=false || usb2_existed=true

    # Mount boot partition
    echo "Mounting boot partition to enable ssh"
    [[ ${my_usb} =~ "mmcblk" ]] && sudo mount /dev/${my_usb}p1 /mnt/usb1 || sudo mount /dev/${my_usb}1 /mnt/usb1
    [[ $? > 0 ]] && echo 'Error mounting boot partition' && exit 1

    # Create empty file ssh in boot partition
    echo "Enabling ssh on image"
    sudo touch /mnt/usb1/ssh && echo -e " + SSH is now enabled" || echo ' - Error enabling SSH... script will continue anyway'

    # Done with boot partition unmount
     sync && sudo umount /mnt/usb1

    # if img_only option set (=true) exit script now.
    $img_only && echo 'image only option configured.  No Pre-Staging will be done, now exiting' && exit 0

    echo -e "\nMounting System partition to Configure ConsolePi auto-install and copy over any pre-config files found in script dir"
    [[ ${my_usb} =~ "mmcblk" ]] && sudo mount /dev/${my_usb}p2 /mnt/usb2 || sudo mount /dev/${my_usb}2 /mnt/usb2
    [[ $? > 0 ]] && echo 'Fatal Error mounting system partition' && exit 1

    #Configure simple psk SSID based on params in this script
    if $configure_wpa_supplicant; then
        echo -e "Configuring wpa_supplicant.conf | defining ${ssid}"
        sudo echo "country=${wlan_country}" >> "/mnt/usb2/etc/wpa_supplicant/wpa_supplicant.conf"
        sudo echo "network={" >> "/mnt/usb2/etc/wpa_supplicant/wpa_supplicant.conf"
        sudo echo "    ssid=\"${ssid}\"" >> "/mnt/usb2/etc/wpa_supplicant/wpa_supplicant.conf"
        sudo echo "    psk=\"${psk}\"" >> "/mnt/usb2/etc/wpa_supplicant/wpa_supplicant.conf"
        [[ $priority > 0 ]] && sudo echo "    priority=${priority}" >> "/mnt/usb2/etc/wpa_supplicant/wpa_supplicant.conf"
        sudo echo "}" >> "/mnt/usb2/etc/wpa_supplicant/wpa_supplicant.conf"
    else
        echo -e "  ~ Script Option to pre-config psk ssid not enabled"
    fi

    # Configure pi user to auto-launch ConsolePi installer on first-login
    if $auto_install; then
        echo -e "\nauto-install enabled, configuring pi user to auto-launch ConsolePi installer on first-login\n"
        echo '#!/usr/bin/env bash' > /mnt/usb2/usr/local/bin/consolepi-install

        # echo 'branch=$(cd /etc/ConsolePi && sudo git status | head -1 | awk '{print $3}')' >> /mnt/usb2/usr/local/bin/consolepi-install
        # echo '[ ! "$branch" == "master" ] && echo -e "Script updating ${branch} branch.\n  You are on a development branch."' >> /mnt/usb2/usr/local/bin/consolepi-install
        if [[ "$1" != "dev" ]] && [[ "$HOSTNAME" == "ConsolePi-dev" ]] ; then
            prompt="dev ConsolePi detected run in local dev mode" && get_input
            $input && local_dev=true
        fi

        if $local_dev || ( [ ! -z "$1" ] && [[ "$1" == "dev" ]] ) ; then
            echo '[ ! -f /home/pi/.ssh/id_rsa.pub ] && ssh-keygen && ssh-copy-id pi@consolepi-dev' >> /mnt/usb2/usr/local/bin/consolepi-install
            echo 'sudo ls /root/.ssh | grep -q id_rsa.pub || ( sudo ssh-keygen && sudo ssh-copy-id pi@consolepi-dev )' >> /mnt/usb2/usr/local/bin/consolepi-install
            echo 'sftp pi@consolepi-dev:/etc/ConsolePi/installer/install.sh /tmp/ConsolePi && sudo bash /tmp/ConsolePi local-dev && sudo rm -f /tmp/ConsolePi' >> /mnt/usb2/usr/local/bin/consolepi-install
        else
            echo 'wget -q https://raw.githubusercontent.com/Pack3tL0ss/ConsolePi/master/installer/install.sh -O /tmp/ConsolePi && sudo bash /tmp/ConsolePi && sudo rm -f /tmp/ConsolePi' >> /mnt/usb2/usr/local/bin/consolepi-install
        fi

        sudo echo "consolepi-install" >> /mnt/usb2/home/pi/.bashrc

        # make install command/script executable
        sudo chmod +x /mnt/usb2/usr/local/bin/consolepi-install || echo 'ERROR making consolepi-install command/script executable'
    fi

    # -- pre-stage-configs --
    do_import_configs

    # Done prepping system partition un-mount
    sudo umount /mnt/usb2

    # Remove our mount_points if they didn't happen to already exist when the script started
    ! $usb1_existed && rmdir /mnt/usb1
    ! $usb2_existed && rmdir /mnt/usb2

    # echo -e "\n\n\033[1;32mConsolepi image ready $*\033[m\n\n"
    green Consolepi image ready
    echo "Boot RaspberryPi with this image, if auto-install was disabled in script enter 'consolepi-install' to deploy ConsolePi"
}

# Not implemented yet
parse_args() {
    ret=0
    # initial values
    local_dav=false
    # echo "DEBUG: ${@}"  ## -- DEBUG LINE --
    while (( "$#" )); do
        # echo -e "DEBUG ~ Currently evaluating: '$1'"
        case "$1" in
            -local) # will stop function from exec remaining commands on failure (witout exit 1)
                local_dev=true
                shift
                ;;
            -b) # will result in exit 1 if cmd fails
                branch="$2"
                shift 2
                ;;
            *) ## -*|--*=) # unsupported flags
                echo "Error: Unsupported flag $1" >&2
                exit 1
                ;;
        esac
    done
    return $ret
}

iam=`whoami`
if [ "${iam}" = "root" ]; then
    # (( "$#" )) && parse_args "$@"
    main "$@"
else
    echo 'Script should be ran as root. exiting.'
fi
