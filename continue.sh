#!/bin/bash

source /etc/profile
export PS1="(chroot) ${PS1}"

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

inf "Updating gentoo ebuild repo"
emerge-webrsync
emerge --sync

err "Make sure nothing critical is displayed in news:"
eselect news read
prompt "Press enter."

inf "Rebuilding updates. This *could* take ages"
emerge --verbose --update --deep --newuse @world

inf "Now we're going to configure the USE variable."
inf "Exactly what you do or don't put in here is *mostly* up to you."
inf "Reccomended reading: https://wiki.gentoo.org/wiki/Handbook:AMD64/Installation/Base"
inf "(just the section entitled \"Configuring the USE variable\")"
prompt "Press enter to edit the file"
nano /etc/portage/make.conf
echo "ACCEPT_LICENSE=\"*\"" >> /etc/portage/make.conf

TZ="/usr/share/LMAO/XD"
while [[ ! -f $TZ ]]; do
    prompt "Pick a time zone (Format: America/New_York , Europe/London, etc)"
    PT="$response"
    TZ="/usr/share/zoneinfo/${PT}"
done

echo "$TZ" > /etc/timezone
inf "Set TZ to ${TZ}"
inf "Informing portage..."
emerge --config sys-libs/timezone-data

echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen

clear
prompt "Do you need more locales than just en_US? (y/N)"
echo "MORE=$response"
MORE="$response"

if [[ "$MORE" == "y" || "$MORE" == "Y" ]]; then
    inf "When we open the file, please remove the leading # before any locales you need."
    inf "Then, save and exit.\nPress enter."
    read
    nano /etc/locale.gen
fi

inf "Generating selected locales."
locale-gen

inf "Please select en_US.UTF-8 below:"
eselect locale list
prompt "Press enter"
eselect locale set ${response}

env-update && source /etc/profile && export PS1="(chroot) ${PS1}"

# TODO: Keymap

inf "Emerging kernel sources"
emerge sys-kernel/gentoo-sources
eselect kernel set 1

inf "Emerging genkernel tool"
emerge sys-kernel/genkernel

if [[ -f /efimode ]]; then
    echo "$(cat /diskn)     /boot/efi   vfat    defaults    0 0" >> /etc/fstab
fi

inf "Making kernel"
genkernel all

inf "Ensuring no modules need to be rebuilt"
emerge @module-rebuild

inf "Installing linux-firmware package"
emerge sys-kernel/linux-firmware

inf "Configuring mounts"
emerge sys-fs/genfstab
genfstab -U / > /etc/fstab

inf "We're going to drop you in nano to sanity-check fstab."
prompt "Press enter"
nano /etc/fstab

prompt "System hostname"
sed -i "s/localhost/${response}/g" /etc/conf.d/hostname
HOSTN="${response}"

inf "Emerging netifrc for network config"
emerge --noreplace net-misc/netifrc

ip link show
prompt "Enter the device name that *isn't* 'lo'"
pushd /etc/init.d
ln -s net.lo net.${response}
popd

sed -i 's/::/#::/g' /etc/hosts
sed -i "s/localhost/${HOSTN}.localdomain ${HOSTN} localhost/g" /etc/hosts

inf "Set password for root"
passwd

inf "Installing and enabling syslog daemon"
emerge app-admin/sysklogd
rc-update add sysklogd default

prompt "Would you like a cron daemon? (y/N)"
if [[ "$response" == "y" || "$response" == "Y" ]]; then
    inf "Installing and enabling cron daemon"
    emerge sys-process/cronie
    rc-update add cronie default
fi

prompt "Would you like to add a small utility for file indexing? (y/N)"
if [[ "$response" == "y" || "$response" == "Y" ]]; then
    inf "Installing mlocate for file indexing"
    emerge sys-apps/mlocate
fi

prompt "Would you like to enable SSH for remote access? (y/N)"
if [[ "$response" == "y" || "$response" == "Y" ]]; then
    inf "Enabling ssh daemon"
    rc-update add sshd default
fi

if [[ -f /efimode ]]; then
    inf "Installing VFAT filesystem support"
    emerge sys-fs/dosfstools
fi

inf "Installing dhcp client"
emerge net-misc/dhcpcd

prompt "Will you need WPA2 (wifi) at a later date? (y/N)"
if [[ "$response" == "y" || "$response" == "Y" ]]; then
    inf "Installing iw and wpa_supplicant for wifi configuration (manual)"
    emerge net-wireless/iw net-wireless/wpa_supplicant
fi

if [[ -f /efimode ]]; then
    echo 'GRUB_PLATFORMS="efi-64"' >> /etc/portage/make.conf
fi

inf "Emerging GRUB"
emerge sys-boot/grub:2

if [[ ! -f /efimode ]]; then
    inf "Installing GRUB for MBR/BIOS"
    grub-install $(cat /diskn)
else
    inf "Installing grub for UEFI/EFI"
    grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=Gentoo
fi

inf "Generating GRUB config."
grub-mkconfig -o /boot/grub/grub.cfg

exit