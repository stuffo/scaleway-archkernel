# Maintainer: Stuffo <youremail@domain.com>
pkgname=scaleway-archkernel-git
_pkgname=scaleway-archkernel
pkgver=r10.8e316b1
pkgrel=1
pkgdesc="boot default Arch kernel on Scaleway C1"
arch=('armv7h')
url="https://github.com/stuffo/scaleway-archkernel"
license=('BSD')
depends=('tftp-hpa'
         'cpio'
         'kexec-tools'
         'linux'
         'systemd')
source=("git+https://github.com/stuffo/scaleway-archkernel.git")
md5sums=(SKIP)
install=archkernel-load.install

pkgver() {
	cd "${_pkgname}"
	printf "r%s.%s" "$(git rev-list --count HEAD)" "$(git rev-parse --short HEAD)"
}

package() {
	cd "${srcdir}/${_pkgname}"
	install -Dm644 archkernel-load.service "$pkgdir"/usr/lib/systemd/system/archkernel-load.service
	install -Dm755 archkernel-load.sh "$pkgdir"/usr/bin/archkernel-load.sh
}
