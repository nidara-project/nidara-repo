#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# build-deps.sh — print the pacman packages needed to BUILD this repo, one per
# line. DERIVED, never retyped.
#
# Sources, in order:
#   1. `makedepends` of the PKGBUILD that ships INSIDE the pinned nidara-desktop
#      tag (NIDARA_REF) — the same file build-repo.sh builds nidara with
#   2. PIPELINE, below: the few tools no PKGBUILD can declare because they are
#      not any package's build dep — they are this pipeline's own
# minus `nidara` itself (it is built here, it exists in no pacman repo).
#
# WHY this exists — the trap it closes:
# build-repo.sh runs makepkg with --nodeps on purpose, which means NOTHING
# installs a package's makedepends for it. Until 2026-08-12 the workflow carried
# a HAND-WRITTEN union of them instead, and it drifted in silence:
# `hyprland-protocols` was declared correctly in nidara's PKGBUILD and missing
# from the workflow, so v0.7.0 — the first release to generate Wayland protocol
# glue — died on `missing protocol: …/hyprland-focus-grab-v1.xml` halfway through
# a release. Nothing warned; a declared makedepend was simply absent. Note a
# clean-install VM cannot catch that class of bug either: there the XML arrives
# with Hyprland itself.
#
# So: to add a build dependency, declare it in packaging/nidara/PKGBUILD in
# nidara-desktop — never here. The one exception is source 2, and each line there
# says which step needs it.
#
# ⚠️ Source 1 is now the ONLY PKGBUILD in the union. Until v0.8.0 there were
# nineteen, and the eighteen Astal/AGS ones declared a much wider toolchain
# (meson, ninja, vala, gtk3, networkmanager, wireplumber, …) that was installed
# for them and happened to be there when nidara built. Anything nidara's build
# reaches for now has to be in ITS OWN makedepends, with nothing left to mask an
# omission.
#
# Usage:  bash scripts/build-deps.sh
#         pacman -S --needed --noconfirm $(bash scripts/build-deps.sh)
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "$HERE/pins.env"

# ── 2. tools the pipeline itself needs ───────────────────────────────────────
PIPELINE=(
    base-devel   # makepkg, fakeroot, gcc, pkgconf — the build itself
    git          # actions/checkout, and every PKGBUILD's git source=
    curl         # build-repo.sh fetches the nidara-desktop release tarball
    gnupg        # signing the packages + the repo db (skipped when GPGKEY unset)
)

# Read one array out of a PKGBUILD without letting it leak into this shell:
# sourced in a subshell, and only the array we asked for is printed. `set +u`
# because a PKGBUILD is not written to survive `nounset`.
read_array() { # $1 = PKGBUILD, $2 = array name
    ( set +u; source "$1" >/dev/null 2>&1 || exit 1
      eval "printf '%s\n' \"\${$2[@]:-}\"" )
}

pkgbuilds=()

# ── the nidara-desktop tag's own PKGBUILD ────────────────────────────────────
# Fetched into the SAME cache build-repo.sh builds nidara from, under the exact
# name its source= expects, so this download is not repeated there. Empty
# NIDARA_REF = releases predating the packaging switch (skip, like build-repo.sh).
if [ -n "${NIDARA_REF:-}" ]; then
    nver="${NIDARA_REF#v}"
    ndir="$HERE/.nidara-build"
    tarball="$ndir/nidara-desktop-$nver.tar.gz"
    mkdir -p "$ndir"
    [ -s "$tarball" ] || curl -fsSL \
        "https://github.com/nidara-project/nidara-desktop/archive/refs/tags/$NIDARA_REF.tar.gz" \
        -o "$tarball"
    tar -xzf "$tarball" -C "$ndir" "nidara-desktop-$nver/packaging/nidara/PKGBUILD"
    pkgbuilds+=("$ndir/nidara-desktop-$nver/packaging/nidara/PKGBUILD")
fi

# ── the package this repo builds itself (filtered out of the pacman list) ────
internal=(nidara)

# A union of nothing but PIPELINE means the tag's PKGBUILD never made it into
# the list (empty NIDARA_REF, a failed fetch). Building on four tools would fail
# much later and much less legibly, so say it here.
[ "${#pkgbuilds[@]}" -gt 0 ] || { echo "[ERR] no PKGBUILD to derive from — is NIDARA_REF set in pins.env?" >&2; exit 1; }

deps=("${PIPELINE[@]}")
for p in "${pkgbuilds[@]}"; do
    while read -r d; do
        [ -n "$d" ] && deps+=("$d")
    done < <(read_array "$p" makedepends)
done

# Strip version constraints (`foo>=1.2` is a valid makedepend, not a valid
# `pacman -S` argument), drop the internal packages, sort -u.
for d in "${deps[@]}"; do
    d="${d%%[<>=]*}"
    for i in "${internal[@]}"; do [ "$d" = "$i" ] && continue 2; done
    echo "$d"
done | sort -u
