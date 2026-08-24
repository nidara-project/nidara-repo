#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# build-repo.sh — build the `nidara` package and assemble the pacman repo.
#
# It used to build eighteen dependency packages first (Astal, ags,
# appmenu-glib-translator), each `pacman -U`'d into the build host so the next
# could find it. Nidara v0.8.0 uses none of them, so this builds one package.
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
    pkgfile="$(ls -t "$ndir"/*.pkg.tar.* 2>/dev/null | head -1)"
    [ -n "$pkgfile" ] || { echo "[ERR] makepkg produced no nidara package" >&2; exit 1; }
    cp -f "$pkgfile" "$OUT/"
fi

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
