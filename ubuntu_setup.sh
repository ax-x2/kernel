#!/usr/bin/env bash

set -Eeuo pipefail

if [[ $# -ne 1 ]]; then
    echo "usage: $0 <kernel-version>"
    echo "example: $0 7.3.1"
    exit 1
fi

KERNEL_VERSION="$1"

if [[ ! "$KERNEL_VERSION" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
    echo "ERROR: invalid kernel version: $KERNEL_VERSION"
    exit 1
fi


if [[ ! -f /etc/os-release ]]; then
    echo "ERROR: cannot identify operating system."
    exit 1
fi

source /etc/os-release

if [[ "${ID:-}" != "ubuntu" ]]; then
    echo "ERROR: this script supports ubuntu only."
    exit 1
fi

if [[ "$EUID" -eq 0 ]]; then
    echo "ERROR: run this script as a normal user."
    echo "example: ./setup.sh 7.3.1"
    exit 1
fi

MAJOR="${KERNEL_VERSION%%.*}"

CUSTOM_SUFFIX="${CUSTOM_SUFFIX:-custom}"

if [[ ! "$CUSTOM_SUFFIX" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    echo "ERROR: invalid custom kernel suffix."
    exit 1
fi

JOBS="${JOBS:-$(nproc)}"

if [[ ! "$JOBS" =~ ^[1-9][0-9]*$ ]]; then
    echo "ERROR: invalid JOBS value."
    exit 1
fi

ARCHIVE="linux-${KERNEL_VERSION}.tar.xz"

URL="https://cdn.kernel.org/pub/linux/kernel/v${MAJOR}.x/${ARCHIVE}"

BUILD_ROOT="$HOME/kernel-build"
WORK_DIR="$BUILD_ROOT/$KERNEL_VERSION"
SOURCE_PARENT="$WORK_DIR/src"
SOURCE_DIR="$SOURCE_PARENT/linux-${KERNEL_VERSION}"

CURRENT_CONFIG="/boot/config-$(uname -r)"

mkdir -p "$SOURCE_PARENT"

sudo -v

echo
echo "======================================================"
echo " UBUNTU CUSTOM KERNEL BUILDER"
echo "======================================================"
echo "ubuntu       : $PRETTY_NAME"
echo "kernel       : $KERNEL_VERSION"
echo "suffix       : $CUSTOM_SUFFIX"
echo "CPU jobs     : $JOBS"
echo "build folder : $WORK_DIR"
echo "======================================================"

echo
echo "[1/12] installing build dependencies..."

DEPENDENCIES=(
    build-essential
    gcc
    g++
    debhelper
    debhelper-compat
    make
    bc
    bison
    flex
    libssl-dev
    libelf-dev
    libncurses-dev
    libdw-dev
    dwarves
    zstd
    git
    fakeroot
    dpkg-dev
    rsync
    cpio
    kmod
    wget
    xz-utils
    ca-certificates
    python3
    perl
    openssl
    mokutil
    initramfs-tools
)

sudo apt-get update
sudo apt-get install -y "${DEPENDENCIES[@]}"

echo
echo "[2/12] checking current kernel configuration..."

if [[ ! -f "$CURRENT_CONFIG" ]]; then
    echo "ERROR: configuration not found:"
    echo "$CURRENT_CONFIG"
    exit 1
fi

echo "using: $CURRENT_CONFIG"

echo
echo "[3/12] downloading linux kernel ${KERNEL_VERSION}..."

cd "$SOURCE_PARENT"

if [[ ! -f "$ARCHIVE" ]]; then
    wget -c "$URL"
else
    echo "archive already exists. skipping download."
fi

echo
echo "[4/12] extracting kernel source..."

if [[ ! -d "$SOURCE_DIR" ]]; then
    tar -xJf "$ARCHIVE" -C "$SOURCE_PARENT"
elif [[ ! -f "$SOURCE_DIR/Makefile" ]]; then
    echo "ERROR: incomplete source directory."
    exit 1
else
    echo "source directory already exists."
fi

cd "$SOURCE_DIR"

echo
echo "[5/12] configuring kernel..."

if [[ ! -f .config ]]; then
    echo "copying current ubuntu kernel configuration..."
    cp -v "$CURRENT_CONFIG" .config
else
    echo "existing .config found. preserving configuration."
fi

cp .config "$WORK_DIR/config-backup-$(date +%Y%m%d-%H%M%S)"

scripts/config --set-str LOCALVERSION "-${CUSTOM_SUFFIX}"

# avoid missing ubuntu certificate paths
scripts/config --set-str SYSTEM_TRUSTED_KEYS ""
scripts/config --set-str SYSTEM_REVOCATION_KEYS ""

make olddefconfig

echo
echo "opening kernel menuconfig..."

make menuconfig

# sync configuration
make olddefconfig

cp .config "$WORK_DIR/config-final"

KERNEL_RELEASE="$(make -s kernelrelease)"

echo
echo "kernel release: $KERNEL_RELEASE"

echo
echo "[6/12] building kernel debian packages..."

echo "using $JOBS parallel jobs."
echo "build log: $WORK_DIR/build.log"

make -j"$JOBS" bindeb-pkg \
    KDEB_PKGVERSION="${KERNEL_VERSION}-1" \
    2>&1 | tee "$WORK_DIR/build.log"

echo
echo "[7/12] locating generated kernel packages..."

IMAGE_DEB=""
HEADER_DEB=""

for DEB in "$SOURCE_PARENT"/*.deb; do

    [[ -f "$DEB" ]] || continue

    PACKAGE_NAME="$(dpkg-deb -f "$DEB" Package)"

    case "$PACKAGE_NAME" in

        "linux-image-${KERNEL_RELEASE}" | \
        "linux-image-unsigned-${KERNEL_RELEASE}")

            IMAGE_DEB="$DEB"
            ;;

        "linux-headers-${KERNEL_RELEASE}")

            HEADER_DEB="$DEB"
            ;;

    esac

done

if [[ -z "$IMAGE_DEB" ]]; then
    echo "ERROR: kernel image package not found."
    exit 1
fi

if [[ -z "$HEADER_DEB" ]]; then
    echo "ERROR: kernel headers package not found."
    exit 1
fi

echo "kernel image:"
echo "$IMAGE_DEB"

echo
echo "kernel headers:"
echo "$HEADER_DEB"

echo
echo "[8/12] installing kernel packages..."

sudo apt-get install -y "$IMAGE_DEB" "$HEADER_DEB"

echo
echo "[9/12] checking initramfs..."

INITRD="/boot/initrd.img-${KERNEL_RELEASE}"

if [[ ! -f "$INITRD" ]]; then

    echo "generating initramfs..."

    sudo update-initramfs -c -k "$KERNEL_RELEASE"

else

    echo "initramfs already exists."
fi

echo
echo "[10/12] updating GRUB..."

sudo update-grub

if sudo grep -Fq "vmlinuz-${KERNEL_RELEASE}" /boot/grub/grub.cfg; then
    echo "new kernel detected by GRUB."
else
    echo "ERROR: new kernel was not detected by GRUB."
    exit 1
fi

echo "GRUB detected kernel ${KERNEL_RELEASE}."

echo
echo "[11/12] verifying kernel installation..."

echo
echo "installed kernel images:"
ls -lh /boot/vmlinuz-*

echo
echo "installed initramfs:"
ls -lh /boot/initrd.img-*

echo
echo "installed kernel modules:"
ls -d /lib/modules/*

echo
echo "installed debian packages:"
dpkg -l | grep -E 'linux-image|linux-headers' || true

echo
echo "[12/12] checking secure boot..."

mokutil --sb-state || true

echo
echo "IMPORTANT:"
echo "if secure boot is enabled, ensure the custom kernel"
echo "is signed with a key trusted by your firmware/boot chain."
echo "the package build does not automatically enroll a key."

echo
echo "======================================================"
echo " KERNEL BUILD AND INSTALLATION COMPLETED"
echo "======================================================"

echo
echo "kernel version : $KERNEL_RELEASE"
echo "kernel image   : /boot/vmlinuz-${KERNEL_RELEASE}"
echo "initramfs      : $INITRD"
echo "build log      : $WORK_DIR/build.log"
echo
echo "existing ubuntu kernels have not been removed."
echo "======================================================"

read -rp "reboot now? [y/N]: " REBOOT

if [[ "$REBOOT" =~ ^[Yy]$ ]]; then
    sudo reboot
else
    echo
    echo "reboot skipped."
    echo "you can reboot manually when ready. dont skip the reboot."
fi
