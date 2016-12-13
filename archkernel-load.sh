#!/bin/bash 
#
# Rewrite Scaleway initrd and kexec into ARCH kernel
#
# Author: stuffo (https://github.com/stuffo/)
# Location: https://github.com/stuffo/scaleway-archkernel
#

# kernel modules to add to the Scaleway initrd to allow Arch kernel to mount
# nbd devices. Path prefix is /lib/modules/<kernel version>
REQUIRED_MODULES="net/ethernet/marvell/mvneta_bm net/ethernet/marvell/mvneta block/nbd"

# where to account current Arch kernel version
ARCH_KERNEL_STAMP="/boot/.archkernel-version"

# default value initialization
INITRD_KERNEL_VERSION="none"
ARCH_KERNEL_VERSION="wedontknowyet"

set -eu
set -o pipefail
shopt -s nullglob
shopt -s dotglob
umask 022

export LC_ALL=C
export LANG=C
unset LANGUAGE

log() {
    echo "$@" >&2
}

fatal() {
    log "$@"
    log "Exiting."
    exit 1
}

rebuild_initrd() {
    local workdir=$(mktemp -d)

    local tftp_server=$(grep bootserver /proc/net/pnp | cut -f2 -d" ")
    if [ -z "$tftp_server" ] ; then
        tftp_server=10.1.31.34
    fi
    log "Scaleway TFTP server: $tftp_server"

    (cd $workdir && tftp -m binary $tftp_server -c get uboot.bootscript)

    # XXX: maybe one day we can use scw-metadata to do this
    dd if=$workdir/uboot.bootscript of=$workdir/uboot.bootscript.raw ibs=72 skip=1 2> /dev/null
    local orig_initrd=$(grep 'tftp .* initrd/uInitrd-Linux-armv7l' $workdir/uboot.bootscript.raw |cut -f3 -d" ")
    rm -f $workdir/uboot.bootscript $workdir/uboot.bootscript.raw
    if [ -z "$orig_initrd" ] ; then
        fatal "failed to get Scaleway initrd"
    fi
    log "Scaleway initrd: $orig_initrd"

    log "+ get scaleway initrd"
    (cd $workdir && tftp -m binary $tftp_server -c get $orig_initrd $workdir/uInitrd.orig)
    dd if=$workdir/uInitrd.orig of=$workdir/uInitrd.orig.gz ibs=64 skip=1 2> /dev/null
    rm -f $workdir/uInitrd.orig
    log "+ extract scaleway initrd"
    local initrd_dir=$(mktemp -d initrd.XXXXXX)
    ( cd $initrd_dir && gunzip < $workdir/uInitrd.orig.gz | cpio -i --quiet > /dev/null )
    rm -f $workdir/uInitrd.orig.gz

    # copy kernel modules
    local insmod_command=
    local modname mod
    local initrd_mod_dir="$initrd_dir/lib/modules/$ARCH_KERNEL_VERSION"
    mkdir -p $initrd_mod_dir
    for mod in $REQUIRED_MODULES ; do
        log "+ add module $mod to initrd"
        modname=$(basename $mod).ko
        gunzip < /lib/modules/$ARCH_KERNEL_VERSION/kernel/drivers/$mod.ko.gz > $initrd_mod_dir/$modname
        insmod_command=$insmod_command"insmod /lib/modules/$ARCH_KERNEL_VERSION/$modname\n"
    done

    log "+ prepend loading modules before entering scaleway initrd"
    mv $initrd_dir/init $initrd_dir/init.scw
    cat > $initrd_dir/init <<-EOF 
#!/bin/sh 
# this was added by archkernel-load.sh to load Arch kernel modules
# before executing the Scaleway init script. Please do not remove.
/bin/busybox mkdir -p /bin /sbin /etc /proc /sys /newroot /usr/bin /usr/sbin
/bin/busybox --install -s
EOF
    echo -e $insmod_command >> $initrd_dir/init
    echo '. init.scw' >> $initrd_dir/init
    chmod 755 $initrd_dir/init

    log "+ rebuild initrd archive"
    ( cd $initrd_dir && find . -print0 | cpio --quiet --null -o --format=newc | gzip -9 > /boot/uInitrd.gz )

    # record kernel version we just integrated into intird for later
    echo $ARCH_KERNEL_VERSION > $ARCH_KERNEL_STAMP

    rm -fr $initrd_dir $workdir
}

shutdown_initrd_kexec_check() {
    # compat for old initrds which don't know how to kexec
    if ! grep -q 'kexec -e' /run/initramfs/shutdown  ; then
        log "current initrd won't kexec automatically. patching it."
        fixup_shutdown_initrd
    fi
}

fixup_shutdown_initrd() {
    mv /run/initramfs/shutdown /tmp/oldshutdown
    {
        head -n -1 /tmp/oldshutdown
        echo "kexec -e" 
    } > /run/initramfs/shutdown && chmod 755 /run/initramfs/shutdown
    rm -f /tmp/oldshutdown
}

get_kernel_version() {
    local installed_kernel=$(pacman -Q -o /boot/zImage|cut -f5 -d" ")
    ARCH_KERNEL_VERSION=$(pacman -Q -l $installed_kernel |grep '/usr/lib/modules/.*/kernel/$'|cut -f5 -d /)
    if [ -r $ARCH_KERNEL_STAMP ] ; then
        INITRD_KERNEL_VERSION=$(cat $ARCH_KERNEL_STAMP)
    fi
    log "Arch kernel version: $ARCH_KERNEL_VERSION"
    log "Initrd kernel version: $INITRD_KERNEL_VERSION"
}

sanity_checks() {
    [ ${EUID} -eq 0 ] || fatal "Script must be run as root."
    [ ${UID} -eq 0 ] || fatal "Script must be run as root."
    if [ ! -r /proc/sys/kernel/kexec_load_disabled ]  ; then
        fatal "kernel has no kexec support. please change bootscript."
    fi

    if [ ! -x /run/initramfs/sbin/kexec ] ; then
        fatal "current initrd has no kexec binary. kexec will fail."
    fi
}

# 
# main
#
sanity_checks
shutdown_initrd_kexec_check

get_kernel_version

if [ "$ARCH_KERNEL_VERSION" != "$INITRD_KERNEL_VERSION" ] ; then
    rebuild_initrd
fi

# we disable some features of the Scaleway initrd as they are superfluous
# for a kexeced environment 
log "Kexec engaged. Make it So!"
kexec -l /boot/zImage \
    --initrd=/boot/uInitrd.gz \
    --command-line="$(cat /proc/cmdline) \
    is_in_kexec=yes \
    NO_SIGNAL_STATE=1 \
    DONT_FETCH_KERNEL_MODULES=1 \
    NO_NTPDATE=1 \
    archkernel" && systemctl kexec
