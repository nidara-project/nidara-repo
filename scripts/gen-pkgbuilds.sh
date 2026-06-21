#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# gen-pkgbuilds.sh — (re)generate packages/*/PKGBUILD from pins.env.
#
# The PKGBUILDs are COMMITTED (auditable, the goal stated in
# nidara-desktop/packaging/README.md). They are lifted verbatim from the
# generators in nidara-desktop/install.sh (§2 appmenu + astal, §4 ags); the only
# thing that varies between runs is the pinned revision, so this script bakes the
# current pins.env values in. Bump a pin in pins.env, re-run this, commit.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "$HERE/pins.env"

PKGDIR="$HERE/packages"
ASTAL_SHORT="${ASTAL_REF:0:7}"
APPMENU_SHORT="${APPMENU_REF:0:7}"
AGS_VER="${AGS_REF#v}"

emit() { mkdir -p "$PKGDIR/$1"; cat > "$PKGDIR/$1/PKGBUILD"; }

# ── appmenu-glib-translator (built FIRST: libastal-tray links it) ─────────────
emit appmenu-glib-translator <<EOF
pkgname=appmenu-glib-translator
pkgver=25.04.r${APPMENU_SHORT}
pkgrel=1
_commit=${APPMENU_REF}
pkgdesc="DBusMenu→GMenuModel translator (pinned for Nidara)"
arch=(x86_64)
url="https://gitlab.com/vala-panel-project/vala-panel-appmenu"
license=(LGPL3)
depends=()
makedepends=(meson ninja vala gobject-introspection git glib2-devel)
options=(!debug)
source=("vala-panel-appmenu::git+https://gitlab.com/vala-panel-project/vala-panel-appmenu.git#commit=\$_commit")
sha256sums=('SKIP')
build() {
  cd "\$srcdir/vala-panel-appmenu/subprojects/appmenu-glib-translator"
  meson setup build --prefix=/usr --buildtype=release
  meson compile -C build
}
package() {
  cd "\$srcdir/vala-panel-appmenu/subprojects/appmenu-glib-translator"
  DESTDIR="\$pkgdir" meson install -C build
}
EOF

# ── Astal libraries (one package per lib, dependency order — io first) ────────
# name|subdir, mirrors install.sh's astal_pkgs array exactly.
astal_pkgs=(
    "libastal-io|lib/astal/io"
    "astal-quarrel|lib/quarrel"
    "libastal-gtk3|lib/astal/gtk3"
    "libastal-gtk4|lib/astal/gtk4"
    "libastal-apps|lib/apps"
    "libastal-hyprland|lib/hyprland"
    "libastal-mpris|lib/mpris"
    "libastal-network|lib/network"
    "libastal-battery|lib/battery"
    "libastal-notifd|lib/notifd"
    "libastal-bluetooth|lib/bluetooth"
    "libastal-tray|lib/tray"
    "libastal-wireplumber|lib/wireplumber"
    "libastal-greet|lib/greet"
    "libastal-auth|lib/auth"
    "astal-gjs|lang/gjs"
)
for entry in "${astal_pkgs[@]}"; do
    name="${entry%%|*}"
    subdir="${entry##*|}"
    emit "$name" <<EOF
pkgname=${name}
pkgver=0.1.0.r${ASTAL_SHORT}
pkgrel=1
_subdir=${subdir}
_commit=${ASTAL_REF}
pkgdesc="Astal library (${subdir}), pinned for Nidara"
arch=(x86_64)
url="https://github.com/Aylur/astal"
license=(LGPL3)
depends=()
makedepends=(meson ninja vala gobject-introspection git glib2-devel)
options=(!debug)
source=("astal::git+https://github.com/Aylur/astal.git#commit=\$_commit")
sha256sums=('SKIP')
build() {
  cd "\$srcdir/astal/\$_subdir"
  meson setup build --prefix=/usr --buildtype=release
  meson compile -C build
}
package() {
  cd "\$srcdir/astal/\$_subdir"
  DESTDIR="\$pkgdir" meson install -C build
}
EOF
done

# ── AGS CLI (depends on astal-gjs + gjs; needs npm install before meson) ──────
emit aylurs-gtk-shell <<EOF
pkgname=aylurs-gtk-shell
pkgver=${AGS_VER}
pkgrel=1
_ref=${AGS_REF}
pkgdesc="Aylur's GTK Shell (ags) CLI, pinned for Nidara"
arch=(x86_64)
url="https://github.com/Aylur/ags"
license=(GPL3)
depends=(astal-gjs gjs)
makedepends=(meson ninja vala gobject-introspection git nodejs npm go glib2-devel)
options=(!debug)
source=("ags::git+https://github.com/Aylur/ags.git#tag=\$_ref")
sha256sums=('SKIP')
build() {
  cd "\$srcdir/ags"
  npm install
  meson setup build --prefix=/usr --buildtype=release
  meson compile -C build
}
package() {
  cd "\$srcdir/ags"
  DESTDIR="\$pkgdir" meson install -C build
}
EOF

echo "Generated $(find "$PKGDIR" -name PKGBUILD | wc -l) PKGBUILDs from pins.env:"
echo "  ASTAL_REF=$ASTAL_REF  AGS_REF=$AGS_REF  APPMENU_REF=$APPMENU_REF"
