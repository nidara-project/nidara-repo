#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# pkg-fingerprint.sh — what a package INSTALLS, with the build's fingerprints
# wiped off.
#
#     scripts/pkg-fingerprint.sh <pkg.tar.zst>      # -> one sha256 on stdout
#
# Two packages built from the same sources are never byte-identical: makepkg
# stamps a build date, records the exact set of packages present on the builder,
# and writes an .MTREE full of mtimes. So `sha256sum` cannot answer "did this
# actually change", and that question is the one that matters — see issue #18,
# where a republished `nidara-apps-1-1` with new bytes and an unchanged name made
# every warm pacman cache report a corrupted package.
#
# What is deliberately EXCLUDED, and why each one is not a difference:
#
#   .MTREE      — a manifest of mtimes and inode numbers. It describes the same
#                 files the payload already contains, and its content moves on
#                 every build by construction.
#   .BUILDINFO  — the builder's environment: every installed package and its
#                 version at build time. Real information, and none of it reaches
#                 the machine being installed.
#   builddate   — the clock.
#   packager    — who ran makepkg. Different on a laptop and in CI, same package.
#
# What is INCLUDED: every file's path, mode, type and content, every symlink's
# target, and the whole of .PKGINFO apart from those two lines — so a changed
# dependency, a changed version, a changed file or a changed permission all move
# the fingerprint.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

pkg="${1:?usage: pkg-fingerprint.sh <pkg.tar.zst>}"
[ -f "$pkg" ] || { echo "no such package: $pkg" >&2; exit 2; }

d="$(mktemp -d)"
trap 'rm -rf -- "$d"' EXIT

bsdtar -xf "$pkg" -C "$d"

rm -f "$d/.MTREE" "$d/.BUILDINFO"
[ -f "$d/.PKGINFO" ] && sed -i -E '/^(builddate|packager) = /d' "$d/.PKGINFO"

# ⚠️ `find` output is piped through `sort` explicitly rather than trusted: its
# traversal order is the filesystem's, so two extractions of the same package can
# enumerate the same tree in different orders. An unsorted stream would hash
# differently for reasons that are not the package's.
{
    # path, mode, type, and the target when it is a symlink
    ( cd "$d" && find . -mindepth 1 -printf '%p\t%m\t%y\t%l\n' | LC_ALL=C sort )
    # and the content of every regular file, in the same fixed order
    ( cd "$d" && find . -type f -print0 | LC_ALL=C sort -z | xargs -0 -r sha256sum )
} | sha256sum | cut -d' ' -f1
