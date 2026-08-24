# nidara-repo

A small **pacman binary repository** for [Nidara](https://github.com/nidara-project/nidara-desktop):
**`nidara` itself**, packaged from each release tag and GPG-signed.

Without this repo, Nidara's installer builds the package on every machine (minutes
per install or update). With it, it installs in seconds like any other package.

> The package is built in the open by the
> [`build-repo` workflow](.github/workflows/build.yml) with the PKGBUILD that ships
> **inside** the release tag pinned in [`pins.env`](pins.env)
> (`packaging/nidara/` in nidara-desktop), so the recipe can never drift from the
> tree it packages — this repo commits nothing about Nidara's layout.

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
sudo pacman -S nidara             # the whole desktop
nidara-setup                      # one-time setup: greeter, services, user config
```

### Signing

The package **and** the repo database are signed by the build workflow with the
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

That is the whole table, and it was eighteen rows longer until Nidara **v0.8.0**.
The [Astal](https://github.com/Aylur/astal) service libraries, the
[`ags`](https://github.com/Aylur/ags) CLI and `appmenu-glib-translator` were built
and served here because Nidara needed them and Arch does not carry them. Nidara
absorbed all of it — the application host, the bundler, every service and the PAM
layer are its own code now — and v0.8.0 is the first release whose `depends=()`
names none of them, so they came out with it.

They were kept for one day longer than the code needed them, deliberately:
v0.7.2 still declared all eighteen, and pulling a package the **current** release
depends on would leave that release impossible to install fresh. Machines that
already have them keep them — pacman never removes a package merely because it
left a repo — and Nidara's `nidara-setup` prints the exact `pacman -Rns` line to
clear them, without ever running it for you.

`nidara`'s PKGBUILD is deliberately **not** committed here: `build-repo.sh` fetches
the `NIDARA_REF` tag's tarball and builds with the PKGBUILD found inside it,
refusing to publish if the tag, its `VERSION` file and the PKGBUILD's `pkgver`
disagree.

That PKGBUILD's `makedepends` are load-bearing, not decoration: the workflow's
build toolchain is **derived** from them by
[`scripts/build-deps.sh`](scripts/build-deps.sh). `build-repo.sh` runs
`makepkg --nodeps` on purpose, so nothing else installs a build dep — **to add
one, declare it in `packaging/nidara/PKGBUILD`** in nidara-desktop, never in the
workflow. With the eighteen gone, that PKGBUILD is the only source left, and
nothing else's toolchain can mask an omission in it.

## Releasing Nidara

Tag `vX.Y.Z` in `nidara-desktop` **first**, then set `NIDARA_REF=vX.Y.Z` in
`pins.env` (one line) and push — CI fetches the tag's tarball, so a pin ahead of
the tag fails. Pushing to `main` rebuilds and republishes the repo to GitHub
Pages. A **pull request** touching `pins.env` or `scripts/` runs the same build
unsigned and without the publish step — prove it there before merging, and note
that a green PR says nothing about the signature: that branch of the workflow
only runs on `main`.

## Build locally

```bash
sudo pacman -S --needed $(bash scripts/build-deps.sh)   # the same toolchain CI installs
bash scripts/build-repo.sh        # builds the package + the repo db into ./x86_64
```

Needs an Arch system with `base-devel`.

## License

Repository tooling: GPL-3.0 (see [`LICENSE`](LICENSE)).
