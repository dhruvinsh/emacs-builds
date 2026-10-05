# emacs-builds

GNU Emacs 31.1 `.deb` packages for Ubuntu (amd64 only), built in GitHub Actions.

| Package         | Session       | configure                              |
| --------------- | ------------- | -------------------------------------- |
| `emacs-wayland` | Wayland       | `--with-pgtk`                          |
| `emacs-x11`     | Xorg          | `--with-x-toolkit=gtk3 --with-xinput2` |

Both are built for **Ubuntu 24.04** and **26.04** with:

- native compilation, AOT (all bundled Lisp ships as `.eln`)
- tree-sitter, SQLite, native JSON, GnuTLS, libxml2, GMP bignums
- dynamic modules, threads, D-Bus, GSettings, inotify, systemd user unit
- HarfBuzz + Cairo text rendering, LCMS2 colour management
- PNG / JPEG / GIF / TIFF / SVG / WebP / ImageMagick images
- ALSA sound, GPM; uses GNU Mailutils for mail retrieval (`Suggests: mailutils`)

Packages install to `/usr`, `Provides: emacs` and conflict with Ubuntu's own
`emacs-*` packages and with each other, so installing one replaces the other.
Runtime dependencies come from `dpkg-shlibdeps`, including the matching
`libgccjit` so JIT native compilation of your own packages works.

## Install

Grab the `.deb` for your release from [Releases](../../releases):

```bash
sudo apt install ./emacs-wayland_31.1-1~ubuntu26.04_amd64.deb
```

## Release

```bash
git tag v31.1-1 && git push origin v31.1-1
```

The tag is `v<emacs-version>-<package-revision>`. The workflow builds every
release/toolkit combination, installs each into a clean container, runs
`test/smoke.el`, then publishes the `.deb`s and `SHA256SUMS`. Pushes to
`main` and manual runs build and test only.

To pick up a new Emacs, bump `EMACS_VERSION` in `build.sh` (and this README)
and tag.

## Build locally

Needs Docker. This runs the same `build.sh` and `test/test.sh` as CI:

```bash
./local-build.sh 26.04 pgtk                     # -> dist/26.04-pgtk/*.deb
NATIVE_COMP=no ./local-build.sh 24.04 gtk3      # fast packaging-only check
```

A full AOT build takes roughly an hour on a 4-core CI runner.
