#!/bin/bash

TARBALL="https://gentoo.osuosl.org/releases/amd64/autobuilds/20220718T184156Z/stage3-amd64-openrc-20220718T184156Z.tar.xz"
DOWNLOAD_DIR=$(pwd)

inf() {
    echo -e "\e[1m♠ $@\e[0m"
}

err() {
    echo -e "\e[1m\e[31m✗ $@\e[0m"
}

response=""
prompt() {
    printf "\e[1m\e[33m$@ : \e[0m"
    read response
}

if [[ "$EUID" != "0" ]]; then
    err "Run as root"
    exit 1
fi

# TODO: Keymaps in gentoo

clear

inf "Disks:"
fdisk -l | grep Disk | grep sectors --color=never

prompt "Would you like to partition manually? (y/N)"
echo "PMODE=$response"
PMODE="$response"

MANUAL="no"
DISK=""
if [[ "$PMODE" == "y" ]]; then
    MANUAL="yes"
else
    prompt "Install target WILL BE FULLY WIPED"
    echo "DISK=$response"
    DISK="$response"
    if ! fdisk -l ${DISK}; then
        err "Seems like $DISK doesn't exist. Did you typo?"
        exit 1
    fi
fi

if [[ $DISK == *"nvme"* ]]; then
    inf "Seems like this is an NVME disk. Noting"
    NVME="yes"
else
    NVME="no"
fi
echo "NVME=$NVME"

if [[ -d /sys/firmware/efi/efivars ]]; then
    inf "Seems like this machine was booted with EFI. Noting"
    EFI="yes"
else
    EFI="no"
fi
echo "EFI=$EFI"

inf "Setting system clock via network"
timedatectl set-ntp true

mkdir -p /mnt/gentoo

if [[ "$MANUAL" == "no" ]]; then
    echo "Partitioning disk"
    if [[ "$EFI" == "yes" ]]; then
        parted ${DISK} mklabel gpt --script
        parted ${DISK} mkpart fat32 0 300 --script
        parted ${DISK} mkpart ext4 300 100% --script
        inf "Partitioned ${DISK} as an EFI volume"
    else
        parted ${DISK} mklabel msdos --script
        parted ${DISK} mkpart primary ext4 0% 100% --script
        inf "Partitioned ${DISK} as an MBR volume"
    fi

    if [[ "$NVME" == "yes" ]]; then
        if [[ "$EFI" == "yes" ]]; then
            inf "Initializing ${DISK} as NVME EFI"
            mkfs.vfat ${DISK}p1
            mkfs.ext4 ${DISK}p2
            mount ${DISK}p2 /mnt/gentoo
            mkdir -p /mnt/gentoo/boot/efi
            mount ${DISK}p1 /mnt/gentoo/boot/efi
        else
            inf "Initializing ${DISK} as NVME MBR"
            mkfs.ext4 ${DISK}p1
            mount ${DISK}p1 /mnt/gentoo
        fi
    else
        if [[ "$EFI" == "yes" ]]; then
            inf "Initializing ${DISK} as EFI"
            mkfs.vfat ${DISK}1
            mkfs.ext4 ${DISK}2
            mount ${DISK}2 /mnt/gentoo
            mkdir -p /mnt/gentoo/boot/efi
            mount ${DISK}p1 /mnt/gentoo/boot/efi
        else
            inf "Initializing ${DISK} as MBR"
            mkfs.ext4 ${DISK}1
            mount ${DISK}1 /mnt/gentoo
        fi
    fi
else
    clear
    inf "You have chosen manual partitioning."
    inf "We're going to drop to a shell for you to partition, but first, PLEASE READ these notes."
    inf "Before you exit the shell, make sure to format and mount a partition for / at /mnt"
    if [[ "$EFI" == "yes" ]]; then
        mkdir -p /mnt/gentoo/boot/efi
        inf "Additionally, since this machine was booted with UEFI, please make sure to make a 200MB or greater partition"
        inf "of type VFAT and mount it at /mnt/gentoo/boot/efi"
    else
        inf "Please give me the full path of the device you're planning to partition (needed for bootloader installation later)"
        inf "Example: /dev/sda"
        printf ": "
        read DISK
    fi

    CONFDONE="NOPE"

    while [[ "$CONFDONE" == "NOPE" ]]; do
        inf "Press enter to go to a shell."
        read
        bash
        prompt "All set (and partitions mounted?) (y/N)"
        echo "STAT=$response"
        STAT="$response"
        if [[ "$STAT" == "y" ]]; then

            if ! findmnt | grep /mnt/gentoo; then
                err "Are you sure you've mounted the partitions?"
            else
                CONFDONE="YEP"
            fi
        fi
    done
fi

inf "Setting time via network"
ntpd -q -g

pushd /mnt/gentoo

inf "Getting latest(ish) Stage3"
wget $TARBALL

inf "Unpacking tarball"
tar xpvf stage3-*.tar.xz --xattrs-include='*.*' --numeric-owner
rm stage3-*.tar.xz

inf "Setting up sane compilation defaults"
sed -i 's/-O2/-march=native -O2/g' etc/portage/make.conf
procs=$(($(nproc)-1))
echo "MAKEOPTS=-j${procs}" >> etc/portage/make.conf

echo "GENTOO_MIRRORS=\"https://gentoo.osuosl.org/\"" >> etc/portage/make.conf

inf "Setting up gentoo ebuild repo"
mkdir --parents /mnt/gentoo/etc/portage/repos.conf
cp /mnt/gentoo/usr/share/portage/config/repos.conf /mnt/gentoo/etc/portage/repos.conf/gentoo.conf

inf "Copying DNS info for chroot"
cp --dereference /etc/resolv.conf /mnt/gentoo/etc/

inf "Setting up needed mountpoints for chroot"
mount --types proc /proc /mnt/gentoo/proc
mount --rbind /sys /mnt/gentoo/sys
mount --make-rslave /mnt/gentoo/sys
mount --rbind /dev /mnt/gentoo/dev
mount --make-rslave /mnt/gentoo/dev
mount --bind /run /mnt/gentoo/run
mount --make-rslave /mnt/gentoo/run


cp ${DOWNLOAD_DIR}/continue.sh /mnt/gentoo/.
chmod +x /mnt/gentoo/continue.sh

# TODO: Keymap changing

if [[ "$EFI" == "yes" ]]; then
    if [[ "$NVME" == "yes" ]]; then
        echo "${DISK}p1" > /mnt/gentoo/diskn
    else
        echo "${DISK}1" > /mnt/gentoo/diskn
    fi
    touch /mnt/gentoo/efimode
else
    echo ${DISK} > /mnt/gentoo/diskn
fi

chroot /mnt/gentoo /continue.sh 2>&1 | tee /mnt/gentoo/var/citrine.chroot.log
rm /mnt/gentoo/{continue.sh,efimode,diskn}

inf "Chroot complete. Removing temp mounts."
popd
umount -l /mnt/gentoo/dev{/shm,/pts,}
umount -R /mnt/gentoo

inf "Installation should now be complete."
prompt "Press enter to reboot"

reboot
