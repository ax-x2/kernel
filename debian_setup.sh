#!/usr/bin/env bash

set -Eeuo pipefail

if [[ $# -ne 1 ]]; then
    echo "usage: $0 <kernel-version>"
    echo "example: $0 7.2.13"
    exit 1
fi

VERSION="$1"
MAJOR="${VERSION%%.*}"
ARCHIVE="linux-${VERSION}.tar.xz"
SOURCE_DIR="linux-${VERSION}"
URL="https://cdn.kernel.org/pub/linux/kernel/v${MAJOR}.x/${ARCHIVE}"

JOBS="$(nproc)"

for cmd in wget tar make gcc nproc; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "ERROR: required command '$cmd' is missing."
        exit 1
    fi
done

CURRENT_CONFIG="/boot/config-$(uname -r)"

if [[ ! -f "$CURRENT_CONFIG" ]]; then
    echo "ERROR: current kernel configuration not found: $CURRENT_CONFIG"
    exit 1
fi

sudo -v

echo "=========================================="
echo " linux kernel installation"
echo " version : ${VERSION}"
echo " jobs    : ${JOBS}"
echo "=========================================="

echo "[1/10] updating system, installing packages and downloading kernel..."

sudo apt update
sudo apt install -y \
    build-essential \
    gcc \
    g++ \
    make \
    bc \
    bison \
    flex \
    libssl-dev \
    libelf-dev \
    libncurses-dev \
    libdw-dev \
    dwarves \
    zstd \
    git \
    fakeroot \
    dpkg-dev \
    debhelper \
    debhelper-compat \
    rsync \
    cpio \
    kmod \
    wget \
    xz-utils \
    ca-certificates \
    python3 \
    perl \
    openssl \
    mokutil \
    initramfs-tools

wget -c "$URL"

echo "[2/10] extracting kernel source..."
tar -xJf "$ARCHIVE"

cd "$SOURCE_DIR"

echo "[3/10] copying current kernel configuration..."
cp -v "$CURRENT_CONFIG" .config

echo "[4/10] updating kernel configuration..."
make olddefconfig

echo "[5/10] opening menuconfig..."
make menuconfig

echo "[6/10] building kernel image..."
make -j"$JOBS" bzImage

echo "[7/10] building kernel modules..."
make -j"$JOBS" modules

echo "[8/10] installing kernel modules..."
sudo make modules_install

echo "[9/10] installing kernel..."
sudo make install

echo "[10/10] updating GRUB..."
sudo update-grub


echo
echo "===== GRUB ====="
cat /etc/default/grub

echo
echo "===== NETWORK ====="

if [[ -f /etc/network/interfaces ]]; then
    cat /etc/network/interfaces
else
    echo "/etc/network/interfaces does not exist."
fi

echo
sudo fstrim -av

echo
echo "=========================================="
echo " kernel ${VERSION} installed successfully!"
echo "=========================================="

read -rp "reboot now? [y/N]: " REBOOT

if [[ "$REBOOT" =~ ^[Yy]$ ]]; then
    sudo reboot
else
    echo "reboot skipped."
    echo "you can reboot manually when ready."
fi
