#!/usr/bin/env bash

# TODO:
# * proxy support

sleep 1 # prevent the curl logs in overlapping with output

echo ""

echo ">>>>> Load console keymap for installation"
loadkeys de-latin1-nodeadkeys

echo ">>>>> Check for EFI"
if [[ "$(efibootmgr &> /dev/null; echo ${?})" != "0" ]]; then
    echo ">>>>> This script can only be executed on EFI-based systems!"
    echo ">>>>> Please check your hardware or vm settings."
    exit 1
fi


if [[ -z ${INSTALL_DISK} ]]; then
    echo ">>>>> Please enter the physical disk drive to install to (default: /dev/sda)"
    read INSTALL_DISK <&1
fi
if [[ -z ${INSTALL_DISK} ]]; then
    INSTALL_DISK=/dev/sda
fi

if [[ -z ${INSTALL_TIMEZONE} ]]; then
    echo ">>>>> Please enter your timezone (default: Europe/Berlin)"
    read INSTALL_TIMEZONE <&1
fi
if [[ -z ${INSTALL_TIMEZONE} ]]; then
    INSTALL_TIMEZONE="Europe/Berlin"
fi

if [[ -z ${INSTALL_HOSTNAME} ]]; then
    echo ">>>>> Please enter your hostname"
    read INSTALL_HOSTNAME <&1
fi

if [[ -z ${INSTALL_USERNAME} ]]; then
    echo ">>>>> Please enter your loginname (user id)"
    read INSTALL_USERNAME <&1
fi
if [[ -z ${INSTALL_USERCOMMENT} ]]; then
    echo ">>>>> Please enter your name (real name)"
    read INSTALL_USERCOMMENT <&1
fi
if [[ -z ${INSTALL_USERPASS} ]]; then
    echo ">>>>> Please enter your user's password"
    read -s INSTALL_USERPASS <&1
fi
if [[ -z ${INSTALL_ROOTPASS} ]]; then
    echo ">>>>> Please enter the root password"
    read -s INSTALL_ROOTPASS <&1
fi
if [[ -z ${INSTALL_DISKPASS} ]]; then
    echo ">>>>> Please enter the password for the encrypted root partition"
    read -s INSTALL_DISKPASS <&1
fi

echo """>>>>> Input:
- disk: '${INSTALL_DISK}'
- timezone: '${INSTALL_TIMEZONE}'
- hostname: '${INSTALL_HOSTNAME}'
- login: '${INSTALL_USERNAME}'
- name: '${INSTALL_USERCOMMENT}'
>>>>> Are those settings correct? (y/n)"
if [[ -z ${SETTINGS_Q} ]]; then
    read SETTINGS_Q <&1
fi
if [[ "${SETTINGS_Q}" != "y" ]]; then
    exit 1
fi

set -x

echo ">>>>> Enable halt on error"
set -e

echo ">>>>> Set general environment variables"
MIRRORLIST=/etc/pacman.d/mirrorlist

echo ">>>>> Enable ntp through timedatectl"
timedatectl set-ntp true

echo ">>>>> Purge existing partition table on '${INSTALL_DISK}'"
sgdisk --zap-all ${INSTALL_DISK}

echo ">>>>> Create partition tables on '${INSTALL_DISK}'"
sgdisk -n 1::+512M -t 1:ef00 -c 1:boot -n 2:: -t 2:8300 -c 2:system ${INSTALL_DISK}

PART_BOOT=$(fdisk -l ${INSTALL_DISK} | tail -n 2 | awk '{print $1}' | egrep '1$')
PART_ROOT=$(fdisk -l ${INSTALL_DISK} | tail -n 2 | awk '{print $1}' | egrep '2$')

echo ">>>>> Format EFI partition to FAT32"
mkfs.vfat ${PART_BOOT}

echo ">>>>> Create encrypted root device [log output will be disabled to prevent password leaking]"
set +x
printf "${INSTALL_DISKPASS}" | cryptsetup luksFormat ${PART_ROOT} -
printf "${INSTALL_DISKPASS}" | cryptsetup luksOpen ${PART_ROOT} system -
set -x

echo ">>>>> Format encrypted root partition to EXT4"
mkfs.ext4 /dev/mapper/system

echo ">>>>> Mount partitions"
mount /dev/mapper/system /mnt
mkdir /mnt/boot
mount ${PART_BOOT} /mnt/boot

echo ">>>>> Set pacman mirror"
{ grep "oth" ${MIRRORLIST}; cat ${MIRRORLIST}; } > ${MIRRORLIST}.new
mv -f ${MIRRORLIST}.new ${MIRRORLIST}

echo ">>>>> Bootstrap base system"
pacstrap /mnt base linux-zen linux-firmware networkmanager sudo zsh

echo ">>>>> Write partitions to fstab"
genfstab -U /mnt >> /mnt/etc/fstab

echo ">>>>> Create swapfile"
#fallocate -l $(($(getconf _PHYS_PAGES) * $(getconf PAGE_SIZE) / (1024 * 1024 *1024) + 1))G /mnt/swapfile
dd if=/dev/zero of=/mnt/swapfile status=progress bs=1M count=$((($(getconf _PHYS_PAGES) * $(getconf PAGE_SIZE) / 1024 / 1024 / 1024 + 1) * 1024))
chmod 600 /mnt/swapfile
mkswap /mnt/swapfile
swapon /mnt/swapfile
echo '/swapfile none swap defaults 0 0' >> /mnt/etc/fstab

set +x
echo ">>>>> Configure base system in chroot"
arch-chroot /mnt /usr/bin/bash -c """#!/usr/bin/env bash
echo '>>>>>>>>>> Set timezone'
ln -sf /usr/share/zoneinfo/${INSTALL_TIMEZONE} /etc/localtime
echo '>>>>>>>>>> Sync hwclock'
hwclock --systohc
echo '>>>>>>>>>> Include UTF-8 locales for de and en'
egrep '^de_DE.UTF-8' /etc/locale.gen || echo 'de_DE.UTF-8 UTF-8' >> /etc/locale.gen
egrep '^en_US.UTF-8' /etc/locale.gen || echo 'en_US.UTF-8 UTF-8' >> /etc/locale.gen
echo '>>>>>>>>>> Generate locales'
locale-gen
echo '>>>>>>>>>> Set locale'
echo 'LANG=en_US.UTF-8' > /etc/locale.conf
echo '>>>>>>>>>> Set console keymap'
echo 'KEYMAP=de-latin1-nodeadkeys' > /etc/vconsole.conf
echo '>>>>>>>>>> Set hostname'
ls /etc/hostname || echo ${INSTALL_HOSTNAME} > /etc/hostname
echo '>>>>>>>>>> Generate kernel image'
ls /etc/mkinitcpio.conf.l3m.bak || cp -f /etc/mkinitcpio.conf /etc/mkinitcpio.conf.l3m.bak
echo 'HOOKS=(base udev keyboard keymap autodetect modconf block encrypt filesystems resume fsck)' > /etc/mkinitcpio.conf
mkinitcpio -P
echo '>>>>>>>>>> Set root password'
echo 'root:${INSTALL_ROOTPASS}' | chpasswd
echo '>>>>>>>>>> Create new user'
grep ${INSTALL_USERNAME} /etc/passwd || (useradd -s /usr/bin/zsh -m -b /home -c ${INSTALL_USERCOMMENT} ${INSTALL_USERNAME} && echo '${INSTALL_USERNAME}:${INSTALL_USERPASS}' | chpasswd)
groupadd sudo
gpasswd -a '${INSTALL_USERNAME}' sudo
gpasswd -a '${INSTALL_USERNAME}' wheel
echo '%sudo ALL=(ALL) ALL' > /etc/sudoers.d/sudo
echo '%wheel ALL=(ALL) ALL' > /etc/sudoers.d/sudo
echo '>>>>>>>>>> Install bootloader'
bootctl install
echo 'default arch' > /boot/loader/loader.conf
echo '''title   Arch Linux
linux   /vmlinuz-linux-zen
initrd  /initramfs-linux-zen.img
options cryptdevice=UUID=$(blkid -o value ${PART_ROOT} | head -n 1):system:allow-discards root=UUID=$(blkid -o value /dev/mapper/system | head -n 1) resume=UUID=$(blkid -o value /dev/mapper/system | head -n 1) resume_offset=$(filefrag -v /mnt/swapfile | awk 'FNR == 4 {print $4+0}') rw quiet''' > /boot/loader/entries/arch.conf
echo '>>>>>>>>>> Enable NetworkManager'
systemctl enable NetworkManager
swapoff /swapfile
exit 0"""

echo '>>>>> Unmount bootstapped environment'
umount /mnt/boot
umount /mnt
cryptsetup luksClose /dev/mapper/system

echo '>>>>> Reboot into newly installed system in 5 seconds'
sleep 5
#reboot
