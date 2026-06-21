#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# build-repo.sh — build every dependency package and assemble the pacman repo.
#
# Mirrors nidara-desktop/install.sh's build_install_pkg contract: each package is
# makepkg'd, then `pacman -U`'d INTO THE BUILD HOST before the next is built, so
# later Astal libs find earlier ones via pkg-config (Astal has no root meson, the
# libs are standalone and discover each other at build time). makepkg refuses to
# run as root, so when root we drop to $BUILD_USER; pacman -U needs root, so when
# not root we sudo. Same split install.sh uses.
#
# Output: $OUT (default ./x86_64) containing every .pkg.tar.zst plus the repo
# database (nidara.db / nidara.files). repo-add writes those as symlinks; we turn
# them into real files because GitHub Pages does not follow symlinks.
#
# Usage:  OUT=/path/to/x86_64 bash scripts/build-repo.sh
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PKGDIR="$HERE/packages"
OUT="${OUT:-$HERE/x86_64}"
DBNAME="nidara"
BUILD_USER="${BUILD_USER:-builder}"
# Shared source cache: the astal/ags git clones happen once and are reused across
# all 16 astal builds (every astal PKGBUILD pins the same commit).
export SRCDEST="${SRCDEST:-$HERE/.srccache}"

# Build order: appmenu first (tray links it), astal io first … astal-gjs, ags last.
ORDER=(
    appmenu-glib-translator
    libastal-io astal-quarrel libastal-gtk3 libastal-gtk4 libastal-apps
    libastal-hyprland libastal-mpris libastal-network libastal-battery
    libastal-notifd libastal-bluetooth libastal-tray libastal-wireplumber
    libastal-greet libastal-auth astal-gjs
    aylurs-gtk-shell
)

as_builder() { if [ "$(id -u)" -eq 0 ]; then runuser -u "$BUILD_USER" -- "$@"; else "$@"; fi; }
as_root()    { if [ "$(id -u)" -eq 0 ]; then "$@"; else sudo "$@"; fi; }

mkdir -p "$OUT" "$SRCDEST"
if [ "$(id -u)" -eq 0 ]; then
    id "$BUILD_USER" &>/dev/null || useradd -m "$BUILD_USER"
    chown -R "$BUILD_USER" "$PKGDIR" "$SRCDEST" "$OUT"
fi

for pkg in "${ORDER[@]}"; do
    dir="$PKGDIR/$pkg"
    [ -f "$dir/PKGBUILD" ] || { echo "[ERR] missing $dir/PKGBUILD — run scripts/gen-pkgbuilds.sh" >&2; exit 1; }
    echo "──────> building $pkg"
    # -f rebuild, --nodeps (order managed here), --skipinteg (git sources, SKIP sums)
    ( cd "$dir" && as_builder env SRCDEST="$SRCDEST" makepkg -f --noconfirm --nodeps --skipinteg --noprogressbar )
    pkgfile="$(ls -t "$dir"/*.pkg.tar.* 2>/dev/null | head -1)"
    [ -n "$pkgfile" ] || { echo "[ERR] makepkg produced no package in $dir" >&2; exit 1; }
    cp -f "$pkgfile" "$OUT/"
    as_root pacman -U --noconfirm --overwrite '*' "$pkgfile"
done

echo "──────> assembling repo database ($DBNAME.db)"
( cd "$OUT" && repo-add "$DBNAME.db.tar.gz" ./*.pkg.tar.* )

# GitHub Pages serves static files and does NOT follow symlinks; repo-add leaves
# nidara.db / nidara.files as symlinks to the .tar.gz. Replace with real copies so
# pacman can fetch `<Server>/nidara.db`.
( cd "$OUT"
  for f in "$DBNAME.db" "$DBNAME.files"; do
      [ -L "$f" ] && cp --remove-destination "$(readlink -f "$f")" "$f"
  done )

echo "──────> repo assembled in $OUT"
ls -1 "$OUT"
