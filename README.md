Rewrite Scaleway initrd and kexec into ARCH kernel 
==================================================

Scaleway C1 boots it's root filesystem via NBD so Scaleway came up with a 
custom kernel that has network and nbd drivers builtin and uses a custom 
initrd to mount the root filesystem before handing over control to the normal
init system. 

This script will allow you to run vanilla Arch kernel on your C1 instance by
adding the required kernel modules to the Scaleway initrd and kexec'ing into
the installed Arch kernel. 

Requirments
-----------
* A Scaleway C1 instance with Arch Linux
* Kernel (bootscript) with KEXEC support (for now only 4.5.7-std works)

How it works
------------
1. Install Arch kernel package
2. fetch bootscript from Scaleway TFTP server
3. fetch Scaleway uInitrd mentioned in bootscript
4. extract uInitrd and add Arch kernel modules (mvneta_bm, mvneta, nbd) 
5. repackage uInitrd into /boots
6. kexec Arch kernel and new uInitrd with original Scaleway /proc/cmdline 
7. run systemctl kexec
8. shutdown initrd will unmount nbd and call kexec -e (execute)
9. new Arch kernel boots and loads modules before handing over to Scaleway 
   init script that does the usual Scaleway magic.
10. Voila! The system is ready now.

Installation
------------
1. clone repo onto your fresh Arch Linux C1 instance
2. run arch-kernel-install.sh
3. do what the script tells you

Configuration
-------------
Edit the script to change default values:
* install_kernel
  which Arch kernel package you want to install and run

Bugs
----
There seems to be a kernel bug in kernel > 4.5 and the kernel will crash 
on reboots while trying to disconnect nbd devices. You need to do a hard reset
via the Scaleway GUI when this happens as the system will hang afterwards.

Currently the only working kernel with KEXEC support on Scaleway seems to be
the default 4.5.7-std-4 kernel. 
