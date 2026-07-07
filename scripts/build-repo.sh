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
# Signing: when $GPGKEY is set (CI always sets it), every package gets a detached
# .sig and the db is signed too (repo-add --sign). The key must already be in the
# invoking user's gpg keyring — any signing failure aborts the build; publishing
# unsigned would break installs that verify with SigLevel = Required. Unset GPGKEY
# (local dev builds) skips signing entirely.
#
# Usage:  OUT=/path/to/x86_64 [GPGKEY=<fpr>] bash scripts/build-repo.sh
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PKGDIR="$HERE/packages"
OUT="${OUT:-$HERE/x86_64}"
DBNAME="nidara"
BUILD_USER="${BUILD_USER:-builder}"
# pins.env is read here only for NIDARA_REF (the nidara-desktop release to
# package, below); the dependency pins in it are consumed by gen-pkgbuilds.sh
# at commit time, not at build time.
# shellcheck source=/dev/null
source "$HERE/pins.env"
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

# ── nidara itself (the desktop package) ───────────────────────────────────────
# Built from the nidara-desktop release tag pinned in pins.env (NIDARA_REF),
# with the PKGBUILD that ships INSIDE that tag (packaging/nidara/) — the recipe
# travels with the release, so it can never drift from the tree it packages,
# and nothing about nidara's layout is committed in this repo. Built LAST on
# purpose: its build (ags bundle ×3) needs the whole Astal/AGS stack, which the
# loop above just installed into this host. The downloaded tarball is placed
# under the exact name the PKGBUILD's source= expects, so makepkg uses it
# instead of re-downloading. Not pacman -U'd: nothing later needs the DE
# installed here. Empty NIDARA_REF skips (releases predating the packaging
# switch).
if [ -n "${NIDARA_REF:-}" ]; then
    echo "──────> building nidara ($NIDARA_REF)"
    nver="${NIDARA_REF#v}"
    ndir="$HERE/.nidara-build"
    rm -rf "$ndir"
    mkdir -p "$ndir"
    curl -fsSL "https://github.com/nidara-project/nidara-desktop/archive/refs/tags/$NIDARA_REF.tar.gz" \
        -o "$ndir/nidara-desktop-$nver.tar.gz"
    tar -xzf "$ndir/nidara-desktop-$nver.tar.gz" -C "$ndir" \
        "nidara-desktop-$nver/packaging/nidara/PKGBUILD" \
        "nidara-desktop-$nver/packaging/nidara/nidara.install" \
        "nidara-desktop-$nver/VERSION"
    cp "$ndir/nidara-desktop-$nver/packaging/nidara/PKGBUILD" \
       "$ndir/nidara-desktop-$nver/packaging/nidara/nidara.install" "$ndir/"
    # Lockstep gate: the tag name, the tag's VERSION file and the PKGBUILD's
    # pkgver are bumped in the same release commit — refuse to publish a
    # package whose label disagrees with the tree it was built from.
    _pkgver="$(grep '^pkgver=' "$ndir/PKGBUILD" | head -1 | cut -d= -f2)"
    _treever="$(tr -d '[:space:]' < "$ndir/nidara-desktop-$nver/VERSION")"
    if [ "$_pkgver" != "$nver" ] || [ "$_treever" != "$nver" ]; then
        echo "[ERR] lockstep violation: tag=$nver VERSION=$_treever pkgver=$_pkgver" >&2
        exit 1
    fi
    if [ "$(id -u)" -eq 0 ]; then chown -R "$BUILD_USER" "$ndir"; fi
    ( cd "$ndir" && as_builder env SRCDEST="$SRCDEST" makepkg -f --noconfirm --nodeps --skipinteg --noprogressbar )
    pkgfile="$(ls -t "$ndir"/*.pkg.tar.* 2>/dev/null | head -1)"
    [ -n "$pkgfile" ] || { echo "[ERR] makepkg produced no nidara package" >&2; exit 1; }
    cp -f "$pkgfile" "$OUT/"
fi

# Sign each package with a detached .sig published next to it — that's what
# pacman (≥6.1) downloads and verifies; repo-add no longer embeds signatures
# in the db. Signing before repo-add keeps the option open either way.
if [ -n "${GPGKEY:-}" ]; then
    echo "──────> signing packages with $GPGKEY"
    for f in "$OUT"/*.pkg.tar.*; do
        [[ "$f" == *.sig ]] && continue
        gpg --batch --yes -u "$GPGKEY" --detach-sign "$f"
    done
fi

echo "──────> assembling repo database ($DBNAME.db)"
( cd "$OUT"
  pkgs=()
  for f in ./*.pkg.tar.*; do [[ "$f" == *.sig ]] || pkgs+=("$f"); done
  # shellcheck disable=SC2086  # ${GPGKEY:+…} expands to two words on purpose
  repo-add ${GPGKEY:+--sign --key "$GPGKEY"} "$DBNAME.db.tar.gz" "${pkgs[@]}" )

# GitHub Pages serves static files and does NOT follow symlinks; repo-add leaves
# nidara.db / nidara.files (and their .sig twins when signing) as symlinks to the
# .tar.gz files. Replace with real copies so pacman can fetch `<Server>/nidara.db`.
( cd "$OUT"
  for f in "$DBNAME.db" "$DBNAME.files" "$DBNAME.db.sig" "$DBNAME.files.sig"; do
      [ -L "$f" ] || continue
      cp --remove-destination "$(readlink -f "$f")" "$f"
  done )

echo "──────> repo assembled in $OUT"
ls -1 "$OUT"
