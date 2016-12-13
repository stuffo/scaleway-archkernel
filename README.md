Run standard Arch Kernels on Scaleway C1 instances
==================================================

## Preface
Scaleway C1 instances have the root filesystem on NBD. Scaleway came up with
a custom kernel that has network and nbd drivers builtin and uses a custom 
initrd to mount the root filesystem before handing over control to the normal
init system. So basically you are stuck with the Scaleway supplied kernels if
you don't want to bake a Scaleway-like initrd. As Arch supplies up-to-date
kernels for ARMv7 you can employ this systemd service to automatically patch 
the original Scaleway initrd on bootup and boot into default Arch kernel.

All this happens by the magic of kexec which Scaleway supports in recent 
initrds (aka bootscripts).

This project was greatly inspired by:  
https://github.com/gh2o/digitalocean-debian-to-arch/blob/debian7/install.sh

## Requirments
* A Scaleway C1 instance with Arch Linux
* Kernel (bootscript) with KEXEC support (4.5.7-std-4 only for now, see Bugs below) 

## Installation
1. make sure your Arch system is up-to-date (`pacman -Syu`)
2. Install an ARMv7 Arch kernel (eg. `pacman -S linux-armv7`)
3. Install this package  
   `pacman -U https://github.com/stuffo/scaleway-archkernel/releases/download/v2.1/scaleway-archkernel-git-r17.0c6d00a-1-armv7h.pkg.tar.xz`
4. `systemctl enable archkernel-load` to enable the systemd service
5. `reboot` 

The system will boot and kexec into the Arch Kernel while booting the Arch 
image. You can see some debug output after bootup using:
`journalctl -u archkernel-load.service`

## Building
1. clone this (`git clone https://github.com/stuffo/scaleway-archkernel.git`)
2. run `makepkg` in the repository to create the Arch package
3. `pacman -U scaleway-archkernel-git*` to install the package

## How it works
1. While booting check if Arch kernel is loaded and matches the initrd.
2. fetch U-Boot bootscript from Scaleway TFTP server
3. fetch Scaleway uInitrd mentioned in bootscript
4. extract uInitrd and add Arch kernel modules (mvneta_bm, mvneta, nbd) 
5. repackage uInitrd into /boot
6. kexec load Arch kernel and new uInitrd with original Scaleway /proc/cmdline 
7. run systemctl kexec
8. shutdown initrd will unmount nbd and call kexec -e (execute)
9. new Arch kernel boots and loads required modules before handing over to 
   Scaleway init script that does the usual Scaleway magic.
10. Voila! The system is ready now.

## Testing
| Package          | Version   | working |
| :--------------- | :-------- | :------ |
| `linux-armv7`    | 4.8.12-1  | X       |
| `linux-armv7-rc` | 4.9.rc8-1 | X       |

## Bugs
There seems to be a kernel bug in kernels > 4.5 and the kernel will crash 
on reboots while trying to disconnect nbd devices. You need to do a hard reset
via the Scaleway GUI when this happens as the system will hang afterwards. This
is not related to this package, Arch or Scaleway but rather seems to be an
upstream kernel problem.

Currently the only working kernel (reboot possible) with KEXEC support on 
Scaleway seems to be the default 4.5.7-std-4 kernel. 
You can use the Scaleway CLI to reset your bootscript to this kernel:
  `scw _patch <instance> bootscript=599b736c-48b5-4530-9764-f04d06ecadc7`

The mv_xor driver throws some stack traces while booting Arch kernels and fails
to load but the kernel will run fine without it. 
