# nidara-repo

A small **pacman binary repository** for [Nidara](https://github.com/nidara-project/nidara-desktop):
**`nidara` itself** (the desktop, packaged from each release tag) plus the few
dependencies it needs that are **not in the official Arch repositories** — the
[Astal](https://github.com/Aylur/astal) service libraries, the
[`ags`](https://github.com/Aylur/ags) CLI, and `appmenu-glib-translator`.

Without this repo, Nidara's installer compiles all of them from source on every
machine (minutes per install/update). With it, they install in seconds as normal
pacman packages.

> Every package is built in the open by the
> [`build-repo` workflow](.github/workflows/build.yml) from the pinned revisions
> in [`pins.env`](pins.env). The `nidara` package is built with the PKGBUILD that
> ships **inside** its release tag (`packaging/nidara/` in nidara-desktop), so the
> recipe can never drift from the tree it packages — this repo commits nothing
> about Nidara's layout.

## Use it

Import the repo's signing key (also committed here as [`nidara.gpg`](nidara.gpg)):

```bash
curl -fsSL https://nidara-project.github.io/nidara-repo/nidara.gpg | sudo pacman-key --add -
sudo pacman-key --lsign-key 80B0AC8C36A43611A8619959B06B716279F755A9
```

Add this to the **end** of `/etc/pacman.conf`:

```ini
[nidara]
SigLevel = Required DatabaseOptional
Server = https://nidara-project.github.io/nidara-repo/$arch
```

Then:

```bash
sudo pacman -Sy
sudo pacman -S nidara             # the whole desktop (pulls the stack below)
nidara-setup                      # one-time setup: greeter, services, user config
```

Individual dependency packages work too, e.g.
`sudo pacman -S aylurs-gtk-shell` (pulls `astal-gjs`).

### Signing

Every package **and** the repo database are signed by the build workflow with the
project's dedicated key:

```
Nidara Package Signing (nidara-repo)
80B0AC8C36A43611A8619959B06B716279F755A9  (ed25519)
```

The public key ships in this repo ([`nidara.gpg`](nidara.gpg)) and at
`https://nidara-project.github.io/nidara-repo/nidara.gpg`; the private key exists
only as a GitHub Actions secret (plus the maintainer's offline backup) — it is
never in the git history. `SigLevel = Required DatabaseOptional` matches the
official Arch repos' semantics: package signatures are mandatory, the (also
signed) database is verified when the signature is present.

## What's in here

| Package | Upstream | Pinned by |
|---|---|---|
| `nidara` | github nidara-project/nidara-desktop (release tags) | `NIDARA_REF` |
| `appmenu-glib-translator` | gitlab vala-panel-appmenu | `APPMENU_REF` |
| `libastal-io`, `astal-quarrel`, `libastal-gtk3/gtk4`, `libastal-apps`, `libastal-hyprland`, `libastal-mpris`, `libastal-network`, `libastal-battery`, `libastal-notifd`, `libastal-bluetooth`, `libastal-tray`, `libastal-wireplumber`, `libastal-greet`, `libastal-auth`, `astal-gjs` | github Aylur/astal | `ASTAL_REF` |
| `aylurs-gtk-shell` (the `ags` CLI) | github Aylur/ags | `AGS_REF` |

The dependency PKGBUILDs under [`packages/`](packages/) are committed and
generated from `pins.env` by [`scripts/gen-pkgbuilds.sh`](scripts/gen-pkgbuilds.sh);
they are lifted verbatim from `nidara-desktop`'s `install.sh`. `nidara`'s own
PKGBUILD is deliberately **not** here — `build-repo.sh` fetches the `NIDARA_REF`
tag's tarball and builds with the PKGBUILD found inside it, refusing to publish
if the tag, its `VERSION` file and the PKGBUILD's `pkgver` disagree.

## Bump a pinned version

```bash
# edit the SHA / tag in pins.env, then:
bash scripts/gen-pkgbuilds.sh   # regenerate the committed PKGBUILDs (deps only)
git add pins.env packages/ && git commit
```

Pushing to `main` triggers the workflow, which rebuilds every package in an Arch
container and republishes the repo to GitHub Pages.

**Releasing Nidara:** tag `vX.Y.Z` in `nidara-desktop`, then set
`NIDARA_REF=vX.Y.Z` in `pins.env` (one line) and push — CI builds the new
`nidara` package from that tag and republishes.

> **Lockstep note:** `nidara-desktop`'s `install.sh` consumes this repo, but it also keeps
> its own `ASTAL_REF` / `AGS_REF` / `APPMENU_REF` (used for its from-source fallback when the
> repo is unreachable, and for the update pin-skip), so those must still be bumped together
> with `pins.env`.

## Build locally

```bash
bash scripts/build-repo.sh        # builds every package + the repo db into ./x86_64
```

Needs an Arch system with `base-devel`. Each package is built then installed before
the next (later Astal libs find earlier ones via `pkg-config`), so the build mutates
the host's installed packages — run it in a container or VM if you don't want that.

## License

Repository tooling: GPL-3.0 (see [`LICENSE`](LICENSE)). The packaged software keeps
its own upstream licenses (Astal/appmenu: LGPL-3.0; ags: GPL-3.0).
