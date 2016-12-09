Rewrite Scaleway initrd and kexec into ARCH kernel 
==================================================

Scaleway C1 boots it's root filesystem via NBD so Scaleway came up with a 
custom kernel that has network and nbd drivers builtin and uses a custom 
initrd to mount the root filesystem before handing over control to the normal
init system. 

This script will allow you to run vanilla Arch kernel on your C1 instance by
adding the required kernel modules to the Scaleway initrd and kexec'ing into
the installed Arch kernel. 

The kexec procedure was greatly inspired by:
`https://github.com/gh2o/digitalocean-debian-to-arch/blob/debian7/install.sh`

Requirments
-----------
* A Scaleway C1 instance with Arch Linux
* Kernel (bootscript) with KEXEC support (eg. 4.5.7-std)

Installation
------------
1. make sure your Arch system is up-to-date (`pacman -Syu`)
2. Install some compatible ARMv7 Arch kernel (eg. `pacman -S linux-armv7`)
2. clone repo (`git clone https://github.com/stuffo/scaleway-arch-kernel-kexec.git`)
2. in the repository type `makepkg`
3. `pacman -U scaleway-archkernel-git*`
4. `systemctl enable archkernel-load`
5. `reboot`

This system will boot and kexec into the Arch Kernel while booting the Arch 
image. You can see some debug output on the running system using:
`journalctl -u archkernel-load.service`

How it works
------------
1. While booting check if Arch kernel is loaded or the version has changed.
2. fetch bootscript from Scaleway TFTP server
3. fetch Scaleway uInitrd mentioned in bootscript
4. extract uInitrd and add Arch kernel modules (mvneta_bm, mvneta, nbd) 
5. repackage uInitrd into /boot
6. kexec Arch kernel and new uInitrd with original Scaleway /proc/cmdline 
7. run systemctl kexec
8. shutdown initrd will unmount nbd and call kexec -e (execute)
9. new Arch kernel boots and loads modules before handing over to Scaleway 
   init script that does the usual Scaleway magic.
10. Voila! The system is ready now.

Bugs
----
There seems to be a kernel bug in kernel > 4.5 and the kernel will crash 
on reboots while trying to disconnect nbd devices. You need to do a hard reset
via the Scaleway GUI when this happens as the system will hang afterwards.

Currently the only working kernel with KEXEC support on Scaleway seems to be
the default 4.5.7-std-4 kernel. You can use the Scaleway CLI to reset your
bootscript to this kernel:
  `scw _patch <instance> bootscript=599b736c-48b5-4530-9764-f04d06ecadc7`
