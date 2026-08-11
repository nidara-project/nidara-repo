#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# gen-pkgbuilds.sh — (re)generate packages/*/PKGBUILD from pins.env.
#
# The PKGBUILDs are COMMITTED (auditable, the goal stated in
# nidara-desktop/packaging/README.md). Their build()/package() are lifted verbatim
# from the generators in nidara-desktop/install.sh (§2 appmenu + astal, §4 ags),
# and the pinned revision is baked in from pins.env — bump a pin, re-run this,
# commit.
#
# `makedepends` is the ONE part that does NOT match install.sh, and deliberately:
# there §1's `pacman -S` has already installed the world before makepkg runs, so
# the generators can get away with a minimal list. Here nothing has. THIS FILE IS
# THE AUTHORITATIVE LIST for both (see nidara-desktop/packaging/README.md).
#
# makedepends are DECLARED PER PACKAGE and they are load-bearing: scripts/
# build-deps.sh derives the CI build toolchain from exactly these arrays, so a
# missing entry here is a package that never gets installed in the build
# container. They are not guesswork — each extra below is the set of
# `dependency()` calls in that lib's meson.build AT THE PINNED REVISION, mapped
# to the Arch package that ships the .pc file:
#
#   glib-2.0/gobject-2.0/gio-2.0/gio-unix-2.0 -> glib2-devel   (the base set)
#   json-glib-1.0 -> json-glib      gdk-pixbuf-2.0 -> gdk-pixbuf2
#   gtk+-3.0 -> gtk3                gtk-layer-shell-0 -> gtk-layer-shell
#   gtk4 -> gtk4                    gtk4-layer-shell-0 -> gtk4-layer-shell
#   wayland-client -> wayland       wayland-protocols -> wayland-protocols
#   libnm -> networkmanager         wireplumber-0.5 -> wireplumber
#   pam -> pam                      appmenu-glib-translator -> (built here)
#
# Astal's own libs (astal-io-0.1, astal-3.0, astal-4-4.0, quarrel-0.1) are listed
# as libastal-*/astal-quarrel: they are real makedepends that happen to be built
# by THIS repo. build-repo.sh's ORDER installs them before their consumers, and
# build-deps.sh filters them out of the pacman list.
#
# Re-derive after bumping ASTAL_REF/AGS_REF: `git grep -n "dependency(" -- lib`
# in the astal checkout. A dep that moves between revisions is invisible here.
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

# Every package needs these: meson/ninja to build, vala for the .vala sources,
# g-ir-compiler (gobject-introspection) for the typelibs, git for the source=,
# glib2-devel for the glib/gobject/gio .pc files.
BASE_MD="meson ninja vala gobject-introspection git glib2-devel"

# ── appmenu-glib-translator (built FIRST: libastal-tray links it) ─────────────
# meson.build: gio-unix-2.0 (base) + gdk-pixbuf-2.0.
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
makedepends=($BASE_MD gdk-pixbuf2)
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
# name|subdir|extra makedepends. The name|subdir pairs mirror install.sh's
# astal_pkgs array exactly; the third field is this lib's meson.build deps on top
# of $BASE_MD (see the header for the .pc → package mapping).
astal_pkgs=(
    "libastal-io|lib/astal/io|"
    "astal-quarrel|lib/quarrel|"
    "libastal-gtk3|lib/astal/gtk3|gtk3 gtk-layer-shell gdk-pixbuf2 wayland wayland-protocols libastal-io"
    "libastal-gtk4|lib/astal/gtk4|gtk4 gtk4-layer-shell libastal-io"
    "libastal-apps|lib/apps|json-glib"
    "libastal-hyprland|lib/hyprland|json-glib"
    "libastal-mpris|lib/mpris|json-glib astal-quarrel"
    "libastal-network|lib/network|networkmanager"
    "libastal-battery|lib/battery|json-glib"
    "libastal-notifd|lib/notifd|json-glib gdk-pixbuf2 astal-quarrel"
    "libastal-bluetooth|lib/bluetooth|"
    "libastal-tray|lib/tray|json-glib gdk-pixbuf2 appmenu-glib-translator"
    "libastal-wireplumber|lib/wireplumber|wireplumber"
    "libastal-greet|lib/greet|json-glib"
    "libastal-auth|lib/auth|pam"
    # lang/gjs picks up the gtk3/gtk4 bindings when their libs are present
    # (`required: false`) — they are installed by then, so declare them: the
    # package's CONTENTS depend on it.
    "astal-gjs|lang/gjs|libastal-io libastal-gtk3 libastal-gtk4"
)
for entry in "${astal_pkgs[@]}"; do
    name="${entry%%|*}"
    rest="${entry#*|}"
    subdir="${rest%%|*}"
    extra="${rest#*|}"
    md="$BASE_MD${extra:+ $extra}"
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
makedepends=($md)
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
# meson.build wants find_program('go'), find_program('gjs') and
# dependency('gtk4-layer-shell-0') — gjs and gtk4-layer-shell are needed to
# BUILD it, not just to run it, and both are easy to mistake for runtime-only.
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
makedepends=($BASE_MD nodejs npm go gjs gtk4-layer-shell astal-gjs)
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
