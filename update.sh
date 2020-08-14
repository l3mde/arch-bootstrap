#!/usr/bin/env bash

sleep 1

BASE="linux-zen-headers base-devel bash bash-completion zsh zsh-completions vim git tig bashtop htop tmux curl xz bzip2 lzop lz4 python python3 lua dnsmasq bluez ppp modemmanager usb_modeswitch zip unzip p7zip unrar openssh libfido2 ntfs-3g dosfstools docker docker-compose strace cmake"

DESKTOP="xorg xfce4 xfce4-goodies gnome-keyring xfce4-screensaver ffmpegthumbnailer poppler-glib libgsf libopenraw thunar-archive-plugin thunar-media-tags-plugin gvfs gvfs-afc gvfs-smb gvfs-gphoto2 gvfs-mtp gvfs-goa gvfs-nfs gvfs-google pulseaudio libcanberra-pulse libcanberra-gstreamer samba pulseaudio-alsa gst-plugins-good gst-plugins-bad gst-libav gst-plugins-ugly pavucontrol hddtemp libdvdcss ghostscript libheif libraw librsvg libwebp libwmf libxml2 openjpeg2 djvulibre libjpeg libpng arc-gtk-theme arc-icon-theme arc-solid-gtk-theme gtk-engine-murrine elementary-icon-theme papirus-icon-theme lightdm-gtk-greeter accountsservice libjpeg-turbo cups menulibre xdg-user-dirs-gtk network-manager-applet blueman pulseaudio-bluetooth"

FONTS="noto-fonts noto-fonts-cjk noto-fonts-emoji noto-fonts-extra adobe-source-code-pro-fonts adobe-source-han-serif-cn-fonts adobe-source-han-sans-cn-fonts adobe-source-han-serif-jp-fonts adobe-source-han-sans-hk-fonts adobe-source-han-serif-kr-fonts adobe-source-han-sans-jp-fonts adobe-source-han-serif-otc-fonts adobe-source-han-sans-kr-fonts adobe-source-han-serif-tw-fonts adobe-source-han-sans-otc-fonts adobe-source-sans-pro-fonts adobe-source-han-sans-tw-fonts adobe-source-serif-pro-fonts x264 x265 zvbi libass libkate libtiger sdl_image srt aalib libcaca libgoom2 projectm"

APPS="firefox thunderbird nextcloud-client mumble discord libreoffice-fresh"

GAMES="dosbox scummvm steam openra openttd openttd-opengfx openttd-opensfx corsix-th-git d1x-rebirth-git d2x-rebirth-git ioquake3-git rvgl-bin"

VLC="vlc aom dav1d libdvdcss libbluray flac twolame libgme vcdimager libmtp libcdio mpg123 protobuf libmicrodns lua-socket live-media libdvdread libdvdnav libogg libshout libmodplug libvpx libvorbis speex opus libtheora"

LEM="git-extras pacman-cleanup-hook spotify systemd-boot-pacman-hook ttf-ms-fonts menulibre makemkv"

sudo sh -c """
echo '>>>>> Initialize l3m repo'
pacman-key --init
curl https://arch.l3m.pub/key.pub | pacman-key --add -
pacman-key --lsign arch@l3m.pub
egrep '^\[l3m\]' /etc/pacman.conf || echo '''[l3m]
Server = https://arch.l3m.pub''' >> /etc/pacman.conf

echo '>>>>> Initialize multilib'
egrep '^\[multilib\]' /etc/pacman.conf || echo '''[multilib]
Include = /etc/pacman.d/mirrorlist''' >> /etc/pacman.conf

echo '>>>>> Update & install packages'
pacman --noconfirm --needed -Syu ${BASE} ${DESKTOP} ${FONTS} ${APPS} ${VLC} ${LEM} ${GAMES}

echo '>>>>> Enable services'
systemctl enable gpm.service
systemctl enable fstrim.timer
systemctl enable lightdm.service
systemctl enable bluetooth.service
systemctl enable docker.service
systemctl enable nscd.service
systemctl enable cups-browsed.service

echo '>>>>> Set default X11 keymap'
localectl --no-convert set-x11-keymap de pc105 nodeadkeys

echo '>>>>> Set login theme'
echo '''[greeter]
theme-name = Arc-Darker
icon-theme-name = Papirus-Dark
font-name = Noto Sans 10
xft-antialias = true
xft-rgba = rgb
xft-hintstyle = hintfull
background = #3465a4
hide-user-image = true
clock-format = %A, %Y-%m-%d, %H:%M:%S
user-background = false
indicators = ~spacer;~clock;~spacer;~language;~power''' > /etc/lightdm/lightdm-gtk-greeter.conf

echo '>>>>> Enable sg module'
echo sg > /etc/modprobe/sg.conf

echo '>>>>> Disable pcspkr'
echo 'blacklist pcspkr' > /etc/modprobe.d/nobeep.conf

echo '>>>>> Add user to groups'
gpasswd -a $(logname) docker"""

mkdir -p ~/Sources/l3mde
git clone https://github.com/l3mde/dotfiles.git ~/Sources/l3mde/dotfiles || (cd ~/Sources/l3mde/dotfiles; git pull)
~/Sources/l3mde/dotfiles/dotdrop -p default install -a -f -V
