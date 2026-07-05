# nidara-repo

A small **pacman binary repository** that ships pre-built copies of the few
dependencies [Nidara](https://github.com/nidara-project/nidara-desktop) needs that
are **not in the official Arch repositories** — the [Astal](https://github.com/Aylur/astal)
service libraries, the [`ags`](https://github.com/Aylur/ags) CLI, and
`appmenu-glib-translator`.

Without this repo, Nidara's installer compiles all of them from source on every
machine (minutes per install/update). With it, they install in seconds as normal
pacman packages.

> This repo contains **only third-party, open-source dependencies** — none of
> Nidara's own code. Every package is built in the open by the
> [`build-repo` workflow](.github/workflows/build.yml) from the pinned revisions
> in [`pins.env`](pins.env).

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
sudo pacman -S aylurs-gtk-shell   # pulls astal-gjs + the libastal-* stack
```

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
| `appmenu-glib-translator` | gitlab vala-panel-appmenu | `APPMENU_REF` |
| `libastal-io`, `astal-quarrel`, `libastal-gtk3/gtk4`, `libastal-apps`, `libastal-hyprland`, `libastal-mpris`, `libastal-network`, `libastal-battery`, `libastal-notifd`, `libastal-bluetooth`, `libastal-tray`, `libastal-wireplumber`, `libastal-greet`, `libastal-auth`, `astal-gjs` | github Aylur/astal | `ASTAL_REF` |
| `aylurs-gtk-shell` (the `ags` CLI) | github Aylur/ags | `AGS_REF` |

The PKGBUILDs under [`packages/`](packages/) are committed and generated from
`pins.env` by [`scripts/gen-pkgbuilds.sh`](scripts/gen-pkgbuilds.sh); they are
lifted verbatim from `nidara-desktop`'s `install.sh`.

## Bump a pinned version

```bash
# edit the SHA / tag in pins.env, then:
bash scripts/gen-pkgbuilds.sh   # regenerate the committed PKGBUILDs
git add pins.env packages/ && git commit
```

Pushing to `main` triggers the workflow, which rebuilds every package in an Arch
container and republishes the repo to GitHub Pages.

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
