#!/usr/bin/env bash
# vim: set expandtab ft=bash ts=4 sw=4:
#
# Install a built .deb into a clean ubuntu container and smoke-test it.
# Installing with apt (not dpkg -i) proves the Depends line resolves.
#
#   docker run --rm -v "$PWD:/work" -w /work ubuntu:26.04 \
#       test/test.sh dist/emacs-wayland_*.deb
#
# Environment: TOOLKIT (gtk3|pgtk), NATIVE_COMP (as passed to build.sh).

set -euo pipefail

deb="${1:?usage: test.sh <package.deb>}"
[[ "${deb}" == /* ]] || deb="${PWD}/${deb}"

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y --no-install-recommends ca-certificates "${deb}"

emacs --batch -Q -l "$(dirname "$0")/smoke.el"
