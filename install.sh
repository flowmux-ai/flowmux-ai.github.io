#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later

set -eu

die() {
    echo "error: $*" >&2
    exit 1
}

[ "$#" -eq 0 ] || die "usage: sh install.sh"

confirm() {
    # stdin contains the script when invoked with curl | sh.
    if ! ( : </dev/tty ) 2>/dev/null; then
        die "confirmation requires a terminal; rerun the installer in a terminal"
    fi
    printf '%s [Y/n] ' "$1" >/dev/tty
    read -r answer </dev/tty || die "could not read confirmation"
    case "$answer" in ""|y|Y|yes|YES) ;; *) die "installation cancelled" ;; esac
}

if [ -x /opt/homebrew/bin/brew ]; then
    PATH="${PATH}:/opt/homebrew/bin:/opt/homebrew/sbin"
    export PATH
fi

system=$(uname -s)
case "$system" in
    Linux) required_commands="curl sha256sum mktemp apt-get dpkg id" ;;
    Darwin) required_commands="curl shasum mktemp hdiutil codesign ditto ps awk launchctl" ;;
    *) die "unsupported OS '$system' (Linux or macOS is required)" ;;
esac
for command in $required_commands; do
    command -v "$command" >/dev/null 2>&1 || die "required command not found: $command"
done

app_dir=${FLOWMUX_MACOS_APP_DIR:-$HOME/Applications}
bin_dir=${FLOWMUX_MACOS_BIN_DIR:-$HOME/.local/bin}
app="$app_dir/Flowmux.app"
running_app_pids() {
    processes=$(ps -ww -axo pid=,comm=) || die "could not check running apps"
    printf '%s\n' "$processes" | while read -r pid executable; do
        if [ "$executable" = "$app/Contents/MacOS/flowmux" ] \
            || [ "$executable" -ef "$app/Contents/MacOS/flowmux" ]; then
            printf '%s\n' "$pid"
        fi
    done
}

if [ "$system" = Darwin ]; then
    architecture=$(uname -m)
    [ "$architecture" = arm64 ] || die "unsupported architecture '$architecture' (Apple Silicon arm64 is required)"
    for name in flowmux flowmuxctl; do
        [ ! -d "$bin_dir/$name" ] || die "refusing to replace directory $bin_dir/$name"
    done
else
    architecture=$(dpkg --print-architecture)
    [ "$architecture" = amd64 ] || die "unsupported architecture '$architecture' (amd64 is required)"
    if [ -r /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        if [ "${ID:-}" = ubuntu ] && dpkg --compare-versions "${VERSION_ID:-0}" lt 24.04; then
            die "Ubuntu ${VERSION_ID:-unknown} is unsupported; Ubuntu 24.04 or later is required"
        fi
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
mountpoint=
install_stage=
cleanup() {
    if [ -n "$mountpoint" ]; then
        hdiutil detach "$mountpoint" >/dev/null || return
    fi
    if [ -n "$install_stage" ]; then
        if [ -e "$install_stage/previous.app" ]; then
            echo "Previous app retained at $install_stage/previous.app" >&2
        else
            rm -rf "$install_stage"
        fi
    fi
    rm -rf "$temporary_directory"
}
trap cleanup 0
trap 'exit 1' HUP INT TERM

if [ "$system" = Darwin ]; then
    package="flowmux-${version}-aarch64-apple-darwin.dmg"
else
    package="flowmux_${version}_amd64.deb"
fi
release_url="https://github.com/flowmux-ai/flowmux/releases/download/${tag}"

echo "==> Downloading Flowmux ${version}"
curl -fsSL "${release_url}/${package}" -o "${temporary_directory}/${package}" \
    || die "release $tag has no downloadable $package; existing installation unchanged"
curl -fsSL "${release_url}/${package}.sha256" -o "${temporary_directory}/${package}.sha256"
# Check only the selected asset, never paths supplied by a checksum file.
checksum=$(awk 'NR == 1 { print $1 }' "${temporary_directory}/${package}.sha256")
case "$checksum" in ''|*[!0-9a-fA-F]*) die "invalid SHA-256 checksum" ;; esac
[ "${#checksum}" -eq 64 ] || die "invalid SHA-256 checksum"
if [ "$system" = Darwin ]; then
    (cd "$temporary_directory" && printf '%s  %s\n' "$checksum" "$package" | shasum -a 256 -c -)
    mkdir "$temporary_directory/mount"
    hdiutil attach -readonly -nobrowse -mountpoint "$temporary_directory/mount" "$temporary_directory/$package"
    mountpoint="$temporary_directory/mount"
    codesign --verify --deep --strict "$mountpoint/Flowmux.app"
    if ! command -v brew >/dev/null 2>&1; then
        confirm "Homebrew is required. Install it and Apple's command-line tools if needed?"
        curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh -o "$temporary_directory/homebrew.sh"
        /bin/bash "$temporary_directory/homebrew.sh" </dev/tty
        PATH="${PATH}:/opt/homebrew/bin:/opt/homebrew/sbin"
        export PATH
    fi
    [ "$(brew --prefix)" = /opt/homebrew ] || die "macOS artifacts require Homebrew at /opt/homebrew"
    missing_formulas=
    for formula in gtk4 libadwaita vte3; do
        if ! brew list --versions "$formula" >/dev/null 2>&1; then
            missing_formulas="$missing_formulas $formula"
        fi
    done
    if [ -n "$missing_formulas" ]; then
        confirm "Install required Homebrew libraries:$missing_formulas?"
        # Formula names come only from the fixed list above.
        brew install $missing_formulas
    fi
    for helper in check-thorvg.py install-thorvg-macos.sh install-thorvg.sh; do
        curl -fsSL "https://flowmux.org/$helper" -o "$temporary_directory/$helper"
    done
    /bin/bash "$temporary_directory/install-thorvg-macos.sh"
    mkdir -p "$app_dir" "$bin_dir"
    install_stage=$(mktemp -d "$app_dir/.flowmux-install.XXXXXX")
    ditto "$mountpoint/Flowmux.app" "$install_stage/Flowmux.app"
    codesign --verify --deep --strict "$install_stage/Flowmux.app"
    running_pids=$(running_app_pids)
    if [ -n "$running_pids" ]; then
        first_pid=$(printf '%s\n' "$running_pids" | head -n 1)
        pending="$app_dir/.Flowmux.app.pending.$first_pid"
        backup="$app_dir/.Flowmux.app.previous.$first_pid"
        update_dir="$HOME/.cache/flowmux"
        helper="$update_dir/deferred-macos-app-swap.sh"
        label="com.flowmux.update.$first_pid"
        mkdir -p "$update_dir"
        curl -fsSL https://flowmux.org/deferred-macos-app-swap.sh -o "$temporary_directory/swap.sh"
        install -m755 "$temporary_directory/swap.sh" "$helper"
        launchctl remove "$label" >/dev/null 2>&1 || true
        rm -rf "$pending"
        mv "$install_stage/Flowmux.app" "$pending"
        launchctl submit -l "$label" -o "$update_dir/update.log" -e "$update_dir/update.log" \
            -- /bin/sh "$helper" "$running_pids" "$pending" "$app" "$backup" \
            || die "could not schedule update; existing app unchanged, new app retained at $pending"
        echo "==> Flowmux ${version} is ready. Quit Flowmux when convenient to finish updating."
    else
        if [ -e "$app" ]; then
            mv "$app" "$install_stage/previous.app"
        fi
        if ! mv "$install_stage/Flowmux.app" "$app"; then
            if [ -e "$install_stage/previous.app" ]; then
                mv "$install_stage/previous.app" "$app" || die "restore failed; previous app retained at $install_stage/previous.app"
            fi
            die "could not install $app"
        fi
        rm -rf "$install_stage/previous.app"
        echo "==> Flowmux ${version} installed at $app"
    fi
    for name in flowmux flowmuxctl; do
        ln -sfn "$app/Contents/MacOS/$name" "$bin_dir/$name"
    done
    echo "==> CLI links: $bin_dir/flowmux and $bin_dir/flowmuxctl (add $bin_dir to PATH if needed)"
    echo "==> Preview: Homebrew runtime libraries required; Developer ID signing and notarization are not available yet."
    exit 0
fi

(cd "$temporary_directory" && printf '%s  %s\n' "$checksum" "$package" | sha256sum -c -)
chmod 755 "$temporary_directory"
chmod 644 "${temporary_directory}/${package}"

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

if ! ( : </dev/tty ) 2>/dev/null; then
    die "confirmation requires a terminal; rerun the installer in a terminal"
fi
echo "==> Installing flowmux ${version}"
install_as_root apt-get update
install_as_root apt-get install "${temporary_directory}/${package}" </dev/tty

echo "==> flowmux ${version} installed"
