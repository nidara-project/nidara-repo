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

Add this to the **end** of `/etc/pacman.conf`:

```ini
[nidara]
SigLevel = Optional TrustAll
Server = https://nidara-project.github.io/nidara-repo/$arch
```

Then:

```bash
sudo pacman -Sy
sudo pacman -S aylurs-gtk-shell   # pulls astal-gjs + the libastal-* stack
```

### Signing

Packages are **unsigned for now** (`SigLevel = Optional TrustAll`); trust rests on
HTTPS + GitHub + the auditable CI build. GPG signing (a `nidara-keyring` package and
`SigLevel = Required`) is planned before any wide / ISO-based distribution.

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

> **Lockstep note:** until `nidara-desktop`'s `install.sh` consumes this repo, its
> `ASTAL_REF` / `AGS_REF` / `APPMENU_REF` must be bumped together with `pins.env`.

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
