#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# build-repo.sh — build the `nidara` packages and assemble the pacman repo.
#
# It used to build eighteen dependency packages first (Astal, ags,
# appmenu-glib-translator), each `pacman -U`'d into the build host so the next
# could find it. Nidara v0.8.0 uses none of them, so this builds three of its own:
# `nidara`, the desktop, from the pinned release tag; `nidara-release`, the
# product's identity, from the pinned nidara-iso tag; and `nidara-apps`, the
# metapackage carrying the curated application set, from a PKGBUILD committed here.
#
# Two pins, because the two versions are independent: the desktop's is cut by
# nidara-desktop and the product's by nidara-iso (see nidara-iso/PRODUCT.md).
#
# makepkg refuses to run as root, so when root we drop to $BUILD_USER.
#
# Output: $OUT (default ./x86_64) containing the .pkg.tar.zst plus the repo
# database (nidara.db / nidara.files). repo-add writes those as symlinks; we turn
# them into real files because GitHub Pages does not follow symlinks.
#
# Signing: when $GPGKEY is set (CI always sets it), the package gets a detached
# .sig and the db is signed too (repo-add --sign). The key must already be in the
# invoking user's gpg keyring — any signing failure aborts the build; publishing
# unsigned would break installs that verify with SigLevel = Required. Unset GPGKEY
# (local dev builds, and every pull request) skips signing entirely.
#
# Usage:  OUT=/path/to/x86_64 [GPGKEY=<fpr>] bash scripts/build-repo.sh
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${OUT:-$HERE/x86_64}"
DBNAME="nidara"
BUILD_USER="${BUILD_USER:-builder}"
# pins.env carries NIDARA_REF, the release to package.
# shellcheck source=/dev/null
source "$HERE/pins.env"
export SRCDEST="${SRCDEST:-$HERE/.srccache}"

as_builder() { if [ "$(id -u)" -eq 0 ]; then runuser -u "$BUILD_USER" -- "$@"; else "$@"; fi; }

mkdir -p "$OUT" "$SRCDEST"
if [ "$(id -u)" -eq 0 ]; then
    id "$BUILD_USER" &>/dev/null || useradd -m "$BUILD_USER"
    chown -R "$BUILD_USER" "$SRCDEST" "$OUT"
fi

# ── nidara (the desktop package, and the only one) ────────────────────────────
# Built from the nidara-desktop release tag pinned in pins.env (NIDARA_REF),
# with the PKGBUILD that ships INSIDE that tag (packaging/nidara/) — the recipe
# travels with the release, so it can never drift from the tree it packages,
# and nothing about nidara's layout is committed in this repo. Its build needs
# only what its own makedepends declare — the toolchain step installs exactly
# those (scripts/build-deps.sh). The downloaded tarball is placed
# under the exact name the PKGBUILD's source= expects, so makepkg uses it
# instead of re-downloading. Not pacman -U'd: nothing later needs the DE
# installed here. Empty NIDARA_REF skips (releases predating the packaging
# switch).
if [ -n "${NIDARA_REF:-}" ]; then
    echo "──────> building nidara ($NIDARA_REF)"
    nver="${NIDARA_REF#v}"
    ndir="$HERE/.nidara-build"
    tarball="$ndir/nidara-desktop-$nver.tar.gz"
    # The tarball is KEPT between runs and only fetched when absent: scripts/
    # build-deps.sh downloads it to this exact path to read the makedepends out
    # of the very PKGBUILD built below, so in CI it is already here. Everything
    # else in the dir is rebuilt from scratch.
    mkdir -p "$ndir"
    rm -rf "$ndir/nidara-desktop-$nver" "$ndir/src" "$ndir/pkg"
    rm -f "$ndir"/*.pkg.tar.*
    [ -s "$tarball" ] || curl -fsSL \
        "https://github.com/nidara-project/nidara-desktop/archive/refs/tags/$NIDARA_REF.tar.gz" \
        -o "$tarball"
    tar -xzf "$tarball" -C "$ndir" \
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
    # EVERY package this PKGBUILD produced, not the newest one. From the next
    # nidara-desktop release on, it is a SPLIT package — `nidara` plus
    # `nidara-installer`, the live medium's graphical installer (landed
    # 2026-08-25) — and the old `ls -t | head -1` would have published exactly
    # one of them, chosen by whichever file makepkg happened to write last.
    # Written BEFORE that tag exists on purpose: this is the consumer, and a
    # consumer that learns about the split when the release lands learns it from
    # a repo that is missing a package. The dir is emptied of
    # packages above, so a glob here can only match this build's output.
    _built=0
    for pkgfile in "$ndir"/*.pkg.tar.*; do
        [ -e "$pkgfile" ] || continue
        case "$pkgfile" in *.sig) continue ;; esac
        cp -f "$pkgfile" "$OUT/"
        echo "         → $(basename "$pkgfile")"
        _built=$((_built + 1))
    done
    [ "$_built" -gt 0 ] || { echo "[ERR] makepkg produced no nidara package" >&2; exit 1; }
fi

# ── nidara-release (the product's identity) ───────────────────────────────────
# One file — /etc/os-release — carrying the PRODUCT's version, which is a
# different number from the desktop's and derives from nothing (nidara-iso's
# PRODUCT.md). Same shape as `nidara` above and for the same reason: the recipe
# travels inside the tag it belongs to, so this repo commits nothing about
# nidara-iso's layout, and cutting a product version IS tagging that repo and
# moving the pin here.
#
# It is fetched from nidara-iso, not nidara-desktop, because renaming somebody's
# operating system is the product's act and not the desktop's — `install.sh` runs
# on an Arch someone already uses and must never do it.
#
# Empty NIDARA_ISO_REF skips: until the first nidara-iso tag exists there is
# nothing to fetch, and a pin ahead of the tag would fail the build.
if [ -n "${NIDARA_ISO_REF:-}" ]; then
    echo "──────> building nidara-release ($NIDARA_ISO_REF)"
    iver="${NIDARA_ISO_REF#v}"
    idir="$HERE/.iso-build"
    isotar="$idir/nidara-iso-$iver.tar.gz"
    mkdir -p "$idir"
    rm -rf "$idir/nidara-iso-$iver" "$idir/src" "$idir/pkg"
    rm -f "$idir"/*.pkg.tar.*
    [ -s "$isotar" ] || curl -fsSL \
        "https://github.com/nidara-project/nidara-iso/archive/refs/tags/$NIDARA_ISO_REF.tar.gz" \
        -o "$isotar"
    tar -xzf "$isotar" -C "$idir" \
        "nidara-iso-$iver/packages/nidara-release/PKGBUILD" \
        "nidara-iso-$iver/VERSION"
    cp "$idir/nidara-iso-$iver/packages/nidara-release/PKGBUILD" "$idir/"
    # Same lockstep gate as nidara's, and it matters more here: this package's
    # only content IS its version. A pkgver that disagrees with the tag would
    # publish a machine-readable lie about which product the system is running.
    _relver="$(grep '^pkgver=' "$idir/PKGBUILD" | head -1 | cut -d= -f2)"
    _isover="$(tr -d '[:space:]' < "$idir/nidara-iso-$iver/VERSION")"
    if [ "$_relver" != "$iver" ] || [ "$_isover" != "$iver" ]; then
        echo "[ERR] lockstep violation: tag=$iver VERSION=$_isover pkgver=$_relver" >&2
        exit 1
    fi
    if [ "$(id -u)" -eq 0 ]; then chown -R "$BUILD_USER" "$idir"; fi
    ( cd "$idir" && as_builder env SRCDEST="$SRCDEST" makepkg -f --noconfirm --nodeps --skipinteg --noprogressbar )
    relfile="$(ls -t "$idir"/*.pkg.tar.* 2>/dev/null | head -1)"
    [ -n "$relfile" ] || { echo "[ERR] makepkg produced no nidara-release package" >&2; exit 1; }
    cp -f "$relfile" "$OUT/"
fi

# ── nidara-apps (the curated application set) ─────────────────────────────────
# A metapackage: no sources, no build, no files — its depends ARE the list. It
# is committed HERE rather than travelling inside a nidara-desktop tag on
# purpose: the set has to be changeable without cutting a desktop release, and
# a desktop release must not be forced to re-decide the app list.
#
# makepkg writes into the PKGBUILD's own directory, so it builds in a copy —
# the committed tree stays clean. --nodeps because a metapackage's depends are
# what it INSTALLS on a user's machine; none of them belong on this builder.
# No pacman -U, no signing or repo-add here either: both loops below already
# sweep everything in $OUT.
echo "──────> building nidara-apps"
adir="$HERE/.apps-build"
rm -rf "$adir"; mkdir -p "$adir"
cp "$HERE/packages/nidara-apps/PKGBUILD" "$adir/"
if [ "$(id -u)" -eq 0 ]; then chown -R "$BUILD_USER" "$adir"; fi
( cd "$adir" && as_builder env SRCDEST="$SRCDEST" makepkg -f --noconfirm --nodeps --skipinteg --noprogressbar )
appsfile="$(ls -t "$adir"/*.pkg.tar.* 2>/dev/null | head -1)"
[ -n "$appsfile" ] || { echo "[ERR] makepkg produced no nidara-apps package" >&2; exit 1; }
cp -f "$appsfile" "$OUT/"

# ── nidara-system (what the product changes about Arch itself) ────────────────
# Third layer: not the desktop, not the app set, but the boot splash and the
# system defaults that make an installed machine Nidara rather than Arch with a
# shell on it. It lives HERE and not in nidara-iso for the same reason
# nidara-apps does — its content has to be changeable without cutting a release
# of something else, and a boot default must not require building a 2 GiB image.
# The PKGBUILD's own header carries the full argument.
#
# ⚠️ Unlike every other package here, this one has FILES, and makepkg's source=()
# takes files and URLs but not directories — so its package() reads them out of
# $startdir. That is why this copies the WHOLE package directory and not just
# the PKGBUILD: with a bare PKGBUILD, $startdir/files does not exist and
# package() dies on the first `install`.
echo "──────> building nidara-system"
sdir="$HERE/.system-build"
rm -rf "$sdir"; mkdir -p "$sdir"
cp -r "$HERE/packages/nidara-system/." "$sdir/"
if [ "$(id -u)" -eq 0 ]; then chown -R "$BUILD_USER" "$sdir"; fi
( cd "$sdir" && as_builder env SRCDEST="$SRCDEST" makepkg -f --noconfirm --nodeps --skipinteg --noprogressbar )
sysfile="$(ls -t "$sdir"/*.pkg.tar.* 2>/dev/null | head -1)"
[ -n "$sysfile" ] || { echo "[ERR] makepkg produced no nidara-system package" >&2; exit 1; }
cp -f "$sysfile" "$OUT/"

# Sign the package with a detached .sig published next to it — that's what
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
