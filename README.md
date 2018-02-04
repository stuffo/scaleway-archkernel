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

## Requirements
* A Scaleway C1 instance with Arch Linux
* Kernel (bootscript) with KEXEC support

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

Frist boot will be taking about 20 seconds longer while regenerating the
initrd. Subsequent boots with the same Arch kernel will instantly kexec.

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
| Package          | Version   | working         |
| :--------------- | :-------- | :-------------- |
| `linux-armv7`    | 4.8.12-1  | X               |
| `linux-armv7-rc` | 4.9.rc8-1 | X               |
| `linux-armv7`    | 4.9.0-1   | X               |
| `linux-armv7`    | 4.9.5-1   | X               |
| `linux-armv7`    | 4.9.9-1   | X               |
| `linux-arvm7`    | 4.10.1-1  | X               |
| `linux-arvm7`    | 4.10.10-1 | X               |
| `linux-arvm7`    | 4.14.15-1 | X               |


## Bugs
The mv_xor module throws some stack traces while booting and fails to load but the 
kernel will run fine without it.

On some kernels shutdown/reboot fails because of wired timing issues with nbd and 
network shutdown related to systemd. Never really got to find out what the problem
is as it is painfull to debug with the 9600 console scaleway has on C1 instances. 
If your instance get stuck on reboot/shutdown, just issue a hard reset via web or 
command line client.
