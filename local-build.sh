#!/usr/bin/env bash
# vim: set expandtab ft=bash ts=4 sw=4:
#
# Build and smoke-test a package locally with Docker, exactly as CI does.
#
#   ./local-build.sh 26.04 pgtk
#   NATIVE_COMP=no ./local-build.sh 24.04 gtk3    # fast packaging check

set -euo pipefail

ubuntu="${1:?usage: local-build.sh <ubuntu-release> <gtk3|pgtk>}"
toolkit="${2:?usage: local-build.sh <ubuntu-release> <gtk3|pgtk>}"
out_dir="dist/${ubuntu}-${toolkit}"

cd "$(dirname "$0")"
rm -rf "${out_dir}"
mkdir -p "${out_dir}"

docker_env=(
    -e TOOLKIT="${toolkit}"
    -e NATIVE_COMP="${NATIVE_COMP:-aot}"
    -e EMACS_VERSION="${EMACS_VERSION:-31.1}"
    -e PKG_REVISION="${PKG_REVISION:-1}"
    -e OUT_DIR="/work/${out_dir}"
    -e HOST_UID="$(id -u)"
    -e HOST_GID="$(id -g)"
)

docker run --rm -v "$PWD:/work" -w /work "${docker_env[@]}" \
    "ubuntu:${ubuntu}" ./build.sh "${toolkit}"

docker run --rm -v "$PWD:/work" -w /work "${docker_env[@]}" \
    "ubuntu:${ubuntu}" test/test.sh "${out_dir}"/*.deb
