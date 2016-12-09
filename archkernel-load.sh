#!/bin/bash 
#
# Rewrite Scaleway initrd and kexec into ARCH kernel
#
# Author: stuffo (https://github.com/stuffo/)
# Location: https://github.com/stuffo/scaleway-arch-kernel-kexec
#

set -eu
set -o pipefail
shopt -s nullglob
shopt -s dotglob
umask 022

export LC_ALL=C
export LANG=C
unset LANGUAGE

rebuild_initrd() {
	local workdir=$(mktemp -d)

	local TFTP_SERVER=`grep bootserver /proc/net/pnp | cut -f2 -d" "`
	if [ -z "$TFTP_SERVER" ] ; then
		TFTP_SERVER=10.1.31.34
	fi
	echo "Scaleway TFTP server: $TFTP_SERVER"

	(cd $workdir && tftp -m binary $TFTP_SERVER -c get uboot.bootscript)

	# XXX: maybe one day we can use scw-metadata to do this
	dd if=$workdir/uboot.bootscript of=$workdir/uboot.bootscript.raw ibs=72 skip=1 2> /dev/null
	ORIG_INITRD=`grep 'tftp .* initrd/uInitrd-Linux-armv7l' $workdir/uboot.bootscript.raw |cut -f3 -d" "`
	rm -f $workdir/uboot.bootscript $workdir/uboot.bootscript.raw
	echo "Scaleway initrd: $ORIG_INITRD"

	echo "+ get scaleway initrd"
	(cd $workdir && tftp -m binary $TFTP_SERVER -c get $ORIG_INITRD $workdir/uInitrd.orig)
	dd if=$workdir/uInitrd.orig of=$workdir/uInitrd.orig.gz ibs=64 skip=1 2> /dev/null
	rm -f $workdir/uInitrd.orig
	echo "+ extract scaleway initrd"
	INITRD_DIR=`mktemp -d initrd.XXXXXX`
	( cd $INITRD_DIR && gunzip < $workdir/uInitrd.orig.gz | cpio -i --quiet > /dev/null )
	rm -f $workdir/uInitrd.orig.gz

	# copy kernel modules
	local INSMOD_COMMAND=""
	INITRD_DIR_MODULES="lib/modules/$ARCH_KERNEL_VERSION"
	mkdir -p $INITRD_DIR/$INITRD_DIR_MODULES
	REQUIRED_MODULES="net/ethernet/marvell/mvneta_bm net/ethernet/marvell/mvneta block/nbd"
	for mod in $REQUIRED_MODULES ; do
		echo "+ add module $mod to initrd"
		modname=`basename $mod`
		gunzip < /lib/modules/$ARCH_KERNEL_VERSION/kernel/drivers/$mod.ko.gz > $INITRD_DIR/$INITRD_DIR_MODULES/$modname.ko
		INSMOD_COMMAND=$INSMOD_COMMAND"insmod /lib/modules/$ARCH_KERNEL_VERSION/$modname.ko\n"
	done
	echo $ARCH_KERNEL_VERSION > /boot/.archkernel-version

	echo "+ prepend loading modules before entering scaleway initrd"
	mv $INITRD_DIR/init $INITRD_DIR/init.scw
	{
		cat << EOT 
#!/bin/sh
/bin/busybox mkdir -p /bin /sbin /etc /proc /sys /newroot /usr/bin /usr/sbin
/bin/busybox --install -s
EOT
echo -e $INSMOD_COMMAND
echo '. init.scw'
	} > $INITRD_DIR/init
	chmod 755 $INITRD_DIR/init

	echo "+ rebuild initrd archive"
	( cd $INITRD_DIR && find . -print0 | cpio --quiet --null -o --format=newc | gzip -9 > /boot/uInitrd.gz )
	rm -fr $INITRD_DIR $workdir
}

if [ ! -r /proc/sys/kernel/kexec_load_disabled ]  ; then
	echo "kernel has no kexec support. please change bootscript."
	exit 1
fi

if [ ! -x /run/initramfs/sbin/kexec ] ; then
	echo "current initrd has no kexec binary. kexec will fail."
	exit 1
fi

# compat for old initrds which don't know how to kexec
if ! grep -q 'kexec -e' /run/initramfs/shutdown  ; then
	echo "current initrd won't kexec automatically. patching it."
    mv /run/initramfs/shutdown /tmp/oldshutdown
    {
        head -n -1 /tmp/oldshutdown
        echo "kexec -e" 
    } > /run/initramfs/shutdown && chmod 755 /run/initramfs/shutdown
    rm -f /tmp/oldshutdown
fi

install_kernel=$(pacman -Q -o /boot/zImage|cut -f5 -d" ")
ARCH_KERNEL_VERSION=`pacman -Q -l $install_kernel |grep '/usr/lib/modules/.*/kernel/$'|cut -f5 -d /`
if [ -r /boot/.archkernel-version ] ; then
	INITRD_KERNEL_VERSION=$(cat /boot/.archkernel-version)
else 
	INITRD_KERNEL_VERSION="none"
fi

echo "Arch kernel version: $ARCH_KERNEL_VERSION"
echo "Initrd kernel version: $INITRD_KERNEL_VERSION"
if [ "$ARCH_KERNEL_VERSION" != "$INITRD_KERNEL_VERSION" ] ; then
    rebuild_initrd
fi

kexec -l /boot/zImage \
    --initrd=/boot/uInitrd.gz \
    --command-line="$(cat /proc/cmdline) \
    is_in_kexec=yes \
    NO_SIGNAL_STATE=1 \
    DONT_FETCH_KERNEL_MODULES=1 \
    archkernel" && systemctl kexec
