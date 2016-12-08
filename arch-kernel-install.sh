#!/bin/sh
#
# This script will change the Scaleway initrd to allow kexec'ing vanilla ARCH kernels.
# Currently on works on C1 ARMv7 instances.
#
# Author: stuffo (https://github.com/stuffo/scaleway-arch-kernel-kexec)
#

#set -x

# ARCH kernel to use`
install_kernel="linux-armv7-rc"

# ARCH packages to be installed
install_packages="tftp-hpa cpio"

if [ `uname -m` != 'armv7l' ] ; then
	echo "only armv7l supported."
	exit 1
fi

if [ `whoami` != 'root' ] ; then
	echo "you need to be root."
	exit 1
fi

if ! zgrep -q CONFIG_KEXEC=y /proc/config.gz ; then
	echo "kernel has no kexec support. change bootscript to a kernel with kexec support"
	exit 1
fi

# lets assume we have a working DHCP lease
if [ ! -r /run/systemd/netif/leases/2 ] ; then
	echo "could not get DHCP lease information"
	exit 1
fi

# check if current shutdown initramfs has kexec support
if [ ! -x /run/initramfs/sbin/kexec ] ; then
	echo "current initrd has no kexec binary. kexec will fail."
	exit 1
fi

# compat for old initrds which don't know how to kexec
if ! grep -q 'kexec -e' /run/initramfs/shutdown  ; then
	echo "current initrd won't kexec automatically. patching it."
	head -n -1 /run/initramfs/shutdown > shutdown.new && mv shutdown.new /run/initramfs/shutdown
	echo "kexec -e" >> /run/initramfs/shutdown
	chmod 755 /run/initramfs/shutdown
fi

# make sure we have all required packages installed
echo "+ upgrading ARCH system"
pacman -Syu 
echo "+ installing mandatory packages"
pacman -S --noconfirm --needed $install_packages $install_kernel

ARCH_KERNEL_VERSION=`pacman -Q -l $install_kernel |grep '/usr/lib/modules/.*/kernel/$'|cut -f5 -d /`
echo "ARCH kernel version: $ARCH_KERNEL_VERSION"

# get current TFTP boot server
TFTP_SERVER=`grep SERVER_ADDRESS /run/systemd/netif/leases/2 | cut -f2 -d=`
echo "Scaleway TFTP server: $TFTP_SERVER"

# fetch uboot bootscript
tftp -m binary $TFTP_SERVER -c get uboot.bootscript

# find current initrd in bootscript
# XXX: maybe one day we can use scw-metadata to do this
dd if=uboot.bootscript of=uboot.bootscript.raw ibs=72 skip=1 2> /dev/null
ORIG_INITRD=`grep 'tftp .* initrd/uInitrd-Linux-armv7l' uboot.bootscript.raw |cut -f3 -d" "`
echo "Scaleway initrd: $ORIG_INITRD"

# get initrd and patch it with required kernel modules
echo "+ get scaleway initrd"
tftp -m binary $TFTP_SERVER -c get $ORIG_INITRD uInitrd.orig
dd if=uInitrd.orig of=uInitrd.orig.gz ibs=64 skip=1 2> /dev/null
INITRD_DIR=`mktemp -d initrd.XXXXXX`
cd $INITRD_DIR
echo "+ extract scaleway initrd"
gunzip < ../uInitrd.orig.gz | cpio -i --quiet > /dev/null

# copy kernel modules
INITRD_DIR_MODULES="lib/modules/$ARCH_KERNEL_VERSION"
mkdir -p $INITRD_DIR_MODULES
REQUIRED_MODULES="net/ethernet/marvell/mvneta_bm net/ethernet/marvell/mvneta block/nbd"
for mod in $REQUIRED_MODULES ; do
	echo "+ add module $mod to initrd"
	modname=`basename $mod`
	gunzip < /lib/modules/$ARCH_KERNEL_VERSION/kernel/drivers/$mod.ko.gz > $INITRD_DIR_MODULES/$modname.ko
	INSMOD_COMMAND=$INSMOD_COMMAND"insmod /lib/modules/$ARCH_KERNEL_VERSION/$modname.ko\n"
done

# prepend module loading before entering scw init script
echo "+ prepend loading modules before entering scaleway initrd"
mv init init.scw
{
cat << EOT 
#!/bin/sh
/bin/busybox mkdir -p /bin /sbin /etc /proc /sys /newroot /usr/bin /usr/sbin
/bin/busybox --install -s
EOT
echo -e $INSMOD_COMMAND
echo '. init.scw'
} > init
chmod 755 init

# rebuild initrd
echo "+ rebuild initrd archive"
find . -print0 | cpio --quiet --null -o --format=newc | gzip -9 > /boot/uInitrd.gz
cd $OLDPWD

# cleanup leftovers
echo "+ cleanup"
rm -rf uboot.bootscript uboot.bootscript.raw uInitrd.orig uInitrd.orig.gz $INITRD_DIR

# prepare kexec
echo "+ preparing kexec"
kexec -l /boot/zImage --initrd=/boot/uInitrd.gz --command-line="`cat /proc/cmdline`"

echo "ready to kexec now. Press any key to reboot into new kernel"
read anykey
systemctl kexec
