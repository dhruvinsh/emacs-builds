#!/usr/bin/env bash
# vim: set expandtab ft=bash ts=4 sw=4:
#
# Build a GNU Emacs .deb for the Ubuntu release this script runs on.
#
# Meant to run as root inside a clean ubuntu:<release> container, so the
# package's runtime dependencies are computed against that release only:
#
#   docker run --rm -v "$PWD:/work" -w /work ubuntu:26.04 ./build.sh pgtk
#
# Usage: build.sh [gtk3|pgtk]
#
# Environment:
#   EMACS_VERSION  upstream release to build          (default: 31.1)
#   PKG_REVISION   Debian revision of the package     (default: 1)
#   NATIVE_COMP    aot | yes | no                     (default: aot)
#                  "no" is only useful for a fast packaging smoke test.
#   OUT_DIR        where the .deb is written          (default: ./dist)
#   HOST_UID/GID   chown the output to this owner (for local docker runs)

set -euo pipefail

TOOLKIT="${1:-${TOOLKIT:-pgtk}}"
EMACS_VERSION="${EMACS_VERSION:-31.1}"
PKG_REVISION="${PKG_REVISION:-1}"
NATIVE_COMP="${NATIVE_COMP:-aot}"
OUT_DIR="${OUT_DIR:-$PWD/dist}"
MAINTAINER="${MAINTAINER:-Dhruvin Shah <dhruvin3@gmail.com>}"

GNU_MIRROR="https://ftpmirror.gnu.org/emacs"
GNU_KEYRING_URL="https://ftp.gnu.org/gnu/gnu-keyring.gpg"

WORK_DIR="$(mktemp -d /tmp/emacs-build.XXXXXX)"
SRC_DIR="${WORK_DIR}/src"
STAGE_DIR="${WORK_DIR}/stage"
trap 'rm -rf "${WORK_DIR}"' EXIT

die() {
    echo "error: $*" >&2
    exit 1
}

case "${TOOLKIT}" in
gtk3)
    # X11 build: GTK3 widgets drawing through Cairo, XInput2 for smooth
    # scrolling / touch, m17n + libotf as extra shaping backends under X.
    PKG_NAME="emacs-x11"
    PKG_FLAVOUR="X11, GTK3"
    TOOLKIT_FLAGS=(--with-x-toolkit=gtk3 --with-cairo --with-xinput2)
    TOOLKIT_DEPS=(
        libgtk-3-dev libxpm-dev libxi-dev libxrandr-dev libxfixes-dev
        libxcomposite-dev libxinerama-dev libm17n-dev libotf-dev
    )
    ;;
pgtk)
    # Pure GTK build: native Wayland (also runs under XWayland, but the
    # gtk3 flavour is the better choice on a real X session).
    PKG_NAME="emacs-wayland"
    PKG_FLAVOUR="Wayland, pure GTK"
    TOOLKIT_FLAGS=(--with-pgtk)
    TOOLKIT_DEPS=(libgtk-3-dev)
    ;;
*)
    die "unknown toolkit '${TOOLKIT}' (expected gtk3 or pgtk)"
    ;;
esac

[[ "$(id -u)" -eq 0 ]] || die "run as root (inside a container)"
[[ "$(dpkg --print-architecture)" == "amd64" ]] || die "only amd64 is supported"

# shellcheck source=/dev/null
. /etc/os-release
[[ "${ID}" == "ubuntu" ]] || die "expected an Ubuntu container, got ${ID}"

PKG_VERSION="${EMACS_VERSION}-${PKG_REVISION}~ubuntu${VERSION_ID}"
DEB_FILE="${PKG_NAME}_${PKG_VERSION}_amd64.deb"

echo "==> Building ${DEB_FILE} (native-comp: ${NATIVE_COMP})"

# --------------------------------------------------------------------------
# Build dependencies
# --------------------------------------------------------------------------
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y --no-install-recommends \
    build-essential ca-certificates curl dpkg-dev gpgv pkg-config xz-utils

# libgccjit has to match the compiler configure will use, so follow the
# release's default gcc (13 on 24.04, 15 on 26.04) instead of pinning one.
GCC_MAJOR="$(gcc -dumpversion | cut -d. -f1)"

BUILD_DEPS=(
    "libgccjit-${GCC_MAJOR}-dev"
    libtree-sitter-dev libsqlite3-dev libgnutls28-dev libxml2-dev zlib1g-dev
    libgmp-dev libacl1-dev libselinux1-dev libseccomp-dev libsystemd-dev libdbus-1-dev
    libgpm-dev libncurses-dev libasound2-dev liblcms2-dev
    libharfbuzz-dev libfreetype-dev libfontconfig-dev libcairo2-dev
    libgif-dev libjpeg-dev libpng-dev libtiff-dev librsvg2-dev libwebp-dev
    libmagickwand-dev
    mailutils
    "${TOOLKIT_DEPS[@]}"
)
apt-get install -y --no-install-recommends "${BUILD_DEPS[@]}"

# --------------------------------------------------------------------------
# Fetch and verify the release tarball
# --------------------------------------------------------------------------
mkdir -p "${SRC_DIR}"
cd "${WORK_DIR}"
tarball="emacs-${EMACS_VERSION}.tar.xz"
curl -fsSL --retry 3 -o "${tarball}" "${GNU_MIRROR}/${tarball}"
curl -fsSL --retry 3 -o "${tarball}.sig" "${GNU_MIRROR}/${tarball}.sig"
curl -fsSL --retry 3 -o gnu-keyring.gpg "${GNU_KEYRING_URL}"
gpgv --keyring "${WORK_DIR}/gnu-keyring.gpg" "${tarball}.sig" "${tarball}"
tar -xJf "${tarball}" -C "${SRC_DIR}" --strip-components=1

# --------------------------------------------------------------------------
# Configure, build, stage
# --------------------------------------------------------------------------
cd "${SRC_DIR}"

CONFIGURE_FLAGS=(
    --prefix=/usr
    --sysconfdir=/etc
    --localstatedir=/var
    --libexecdir=/usr/libexec
    --with-native-compilation="${NATIVE_COMP}"
    --with-tree-sitter
    --with-sqlite3
    --with-gnutls
    --with-xml2
    --with-modules
    --with-threads
    --with-libgmp
    --with-dbus
    --with-gsettings
    --with-libsystemd
    --with-file-notification=inotify
    --with-sound=alsa
    --with-mailutils
    --with-harfbuzz
    --with-lcms2
    --with-rsvg
    --with-webp
    --with-imagemagick
    --with-gpm
    "${TOOLKIT_FLAGS[@]}"
)

./configure "${CONFIGURE_FLAGS[@]}" CFLAGS="-O2 -pipe"
make -j"$(nproc)"
make install-strip DESTDIR="${STAGE_DIR}"

# install-info's dpkg trigger rebuilds /usr/share/info/dir; shipping our own
# copy would clash with every other package that has info pages.
rm -f "${STAGE_DIR}/usr/share/info/dir"
# ctags is owned by universal-ctags on Ubuntu; never ship Emacs' copy.
rm -f "${STAGE_DIR}/usr/bin/ctags" "${STAGE_DIR}"/usr/share/man/man1/ctags.1*

# --------------------------------------------------------------------------
# Package
# --------------------------------------------------------------------------
# Runtime deps come from dpkg-shlibdeps over the real executables only: the
# .eln files under native-lisp/ are ELF too, but they link against symbols in
# the emacs binary and would just produce thousands of warnings.
elf_files=()
while IFS= read -r -d '' f; do
    readelf -h "${f}" &>/dev/null && elf_files+=("${f}")
done < <(find "${STAGE_DIR}/usr/bin" "${STAGE_DIR}/usr/libexec" -type f -print0)
((${#elf_files[@]} > 0)) || die "no ELF executables found in staging dir"

mkdir -p "${WORK_DIR}/shlibs/debian"
printf 'Source: emacs\n\nPackage: %s\nArchitecture: amd64\n' "${PKG_NAME}" \
    >"${WORK_DIR}/shlibs/debian/control"
shlibs_depends="$(
    cd "${WORK_DIR}/shlibs" &&
        dpkg-shlibdeps -O "${elf_files[@]}" 2>/dev/null |
        sed -n 's/^shlibs:Depends=//p'
)"
[[ -n "${shlibs_depends}" ]] || die "dpkg-shlibdeps produced no dependencies"

# Both flavours provide "emacs" and conflict with it, so they replace each
# other and Ubuntu's own emacs packages cleanly.
distro_emacs="emacs, emacs-gtk, emacs-pgtk, emacs-lucid, emacs-nox, emacs-common, emacs-bin-common, emacs-el"

mkdir -p "${STAGE_DIR}/DEBIAN"
cat >"${STAGE_DIR}/DEBIAN/control" <<EOF
Package: ${PKG_NAME}
Version: ${PKG_VERSION}
Architecture: amd64
Maintainer: ${MAINTAINER}
Installed-Size: $(du -sk --exclude=DEBIAN "${STAGE_DIR}" | cut -f1)
Depends: ${shlibs_depends}, mailutils
Recommends: fonts-noto-color-emoji
Provides: emacs
Conflicts: ${distro_emacs}
Replaces: ${distro_emacs}
Section: editors
Priority: optional
Homepage: https://www.gnu.org/software/emacs/
Description: GNU Emacs ${EMACS_VERSION} (${PKG_FLAVOUR}) with native compilation
 Upstream GNU Emacs ${EMACS_VERSION} built for Ubuntu ${VERSION_ID} with
 ahead-of-time native compilation of all bundled Lisp, tree-sitter, SQLite,
 GnuTLS, libxml2, dynamic modules, threads, HarfBuzz, Cairo, LCMS2, D-Bus,
 inotify, SVG/WebP/ImageMagick images and GNU Mailutils.
EOF

mkdir -p "${OUT_DIR}"
dpkg-deb -Zxz --build "${STAGE_DIR}" "${OUT_DIR}/${DEB_FILE}"
if [[ -n "${HOST_UID:-}" ]]; then
    chown "${HOST_UID}:${HOST_GID:-${HOST_UID}}" "${OUT_DIR}" "${OUT_DIR}/${DEB_FILE}"
fi

dpkg-deb --info "${OUT_DIR}/${DEB_FILE}"
echo "==> Built ${OUT_DIR}/${DEB_FILE}"
