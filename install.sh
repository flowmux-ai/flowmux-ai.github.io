#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later

set -eu

die() {
    echo "error: $*" >&2
    exit 1
}

[ "$(uname -s)" = Linux ] || die "this installer supports Linux only"

for command in curl sha256sum mktemp apt-get dpkg id; do
    command -v "$command" >/dev/null 2>&1 || die "required command not found: $command"
done

architecture=$(dpkg --print-architecture)
[ "$architecture" = amd64 ] || die "unsupported architecture '$architecture' (amd64 is required)"

if [ -r /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    if [ "${ID:-}" = ubuntu ] && dpkg --compare-versions "${VERSION_ID:-0}" lt 24.04; then
        die "Ubuntu ${VERSION_ID:-unknown} is unsupported; Ubuntu 24.04 or later is required"
    fi
fi

latest_url=$(curl -fsSLI -o /dev/null -w '%{url_effective}' \
    https://github.com/flowmux-ai/flowmux/releases/latest)
tag=${latest_url##*/}
version=${tag#v}
[ "$tag" != "$version" ] || die "invalid release tag '$tag'"

case "$version" in
    ''|*[!0-9.]*|.*|*.|*..*) die "invalid release tag '$tag'" ;;
esac
minor_patch=${version#*.}
patch=${minor_patch#*.}
[ "$minor_patch" != "$version" ] && [ "$patch" != "$minor_patch" ] \
    && [ "${patch#*.}" = "$patch" ] || die "invalid release tag '$tag'"

temporary_directory=$(mktemp -d)
trap 'rm -rf "$temporary_directory"' 0
trap 'exit 1' HUP INT TERM

package="flowmux_${version}_amd64.deb"
release_url="https://github.com/flowmux-ai/flowmux/releases/download/${tag}"

echo "==> Downloading flowmux ${version}"
curl -fsSL "${release_url}/${package}" -o "${temporary_directory}/${package}"
curl -fsSL "${release_url}/${package}.sha256" -o "${temporary_directory}/${package}.sha256"
(cd "$temporary_directory" && sha256sum -c "${package}.sha256")

if [ "$(id -u)" -ne 0 ] && ! command -v sudo >/dev/null 2>&1; then
    die "sudo is required to install flowmux"
fi

install_as_root() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    else
        sudo "$@"
    fi
}

echo "==> Installing flowmux ${version}"
install_as_root apt-get update
install_as_root apt-get install -y "${temporary_directory}/${package}"

echo "==> flowmux ${version} installed"
