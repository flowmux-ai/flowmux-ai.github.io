#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later

set -eu

if [ "${FLOWMUX_INSTALL_MOCK:-}" = 1 ]; then
    case ${0##*/} in
        uname)
            if [ "${1:-}" = -m ]; then
                echo "${TEST_ARCHITECTURE:-arm64}"
            else
                echo "${TEST_OS:-Linux}"
            fi
            ;;
        dpkg)
            if [ "$1" = --print-architecture ]; then
                echo "${TEST_ARCHITECTURE:-amd64}"
            else
                exit 1
            fi
            ;;
        curl)
            output=
            url=
            while [ "$#" -gt 0 ]; do
                case $1 in
                    -o) output=$2; shift 2 ;;
                    -w) shift 2 ;;
                    http*) url=$1; shift ;;
                    *) shift ;;
                esac
            done
            printf 'curl %s\n' "$url" >> "$TEST_LOG"
            case $url in
                */releases/latest)
                    printf '%s' 'https://github.com/flowmux-ai/flowmux/releases/tag/v9.8.7'
                    ;;
                *.sha256)
                    package_path=${output%.sha256}
                    package=${package_path##*/}
                    directory=${package_path%/*}
                    if [ "${TEST_BAD_CHECKSUM:-0}" = 1 ]; then
                        printf '%064d  %s\n' 0 "$package" > "$output"
                    else
                        (cd "$directory" && shasum -a 256 "$package" > "$package.sha256")
                    fi
                    ;;
                *.deb|*.dmg)
                    [ "${TEST_MISSING_ASSET:-0}" != 1 ] || exit 22
                    printf 'test package' > "$output"
                    ;;
                *)
                    exit 1
                    ;;
            esac
            ;;
        apt-get)
            printf 'apt-get' >> "$TEST_LOG"
            printf ' %s' "$@" >> "$TEST_LOG"
            printf '\n' >> "$TEST_LOG"
            ;;
        brew)
            printf 'brew %s\n' "$*" >> "$TEST_LOG"
            case "$1" in
                --prefix) echo /opt/homebrew ;;
                list) [ "${TEST_MISSING_LIBRARY:-}" != "$3" ] ;;
                install) : ;;
                *) exit 1 ;;
            esac
            ;;
        ps)
            if [ "${TEST_RUNNING:-0}" = 1 ]; then
                printf '%s/Flowmux.app/Contents/MacOS/flowmux\n' "$FLOWMUX_MACOS_APP_DIR"
            elif [ "${TEST_RUNNING:-0}" = 2 ]; then
                printf '%s/flowmux\n' "$FLOWMUX_MACOS_BIN_DIR"
            fi
            ;;
        codesign)
            printf 'codesign %s\n' "$*" >> "$TEST_LOG"
            [ "${TEST_BAD_SIGNATURE:-0}" != 1 ]
            ;;
        hdiutil)
            printf 'hdiutil %s\n' "$*" >> "$TEST_LOG"
            if [ "$1" = attach ]; then
                while [ "$1" != -mountpoint ]; do shift; done
                mkdir -p "$2/Flowmux.app/Contents/MacOS"
                printf 'new app' > "$2/Flowmux.app/Contents/MacOS/flowmux"
                printf 'new cli' > "$2/Flowmux.app/Contents/MacOS/flowmuxctl"
            fi
            ;;
        ditto)
            cp -R "$1" "$2"
            ;;
        mv)
            case "$1" in
                */.flowmux-install.*/Flowmux.app)
                    [ "${TEST_FAIL_APP_MOVE:-0}" != 1 ] || exit 1 ;;
            esac
            exec /bin/mv "$@"
            ;;
        sudo)
            exec "$@"
            ;;
        *)
            exit 1
            ;;
    esac
    exit 0
fi

root=$(CDPATH= cd "$(dirname "$0")" && pwd)
temporary_directory=$(mktemp -d)
trap 'rm -rf "$temporary_directory"' 0
mkdir "$temporary_directory/bin"

for command in uname dpkg curl apt-get sudo brew ps codesign hdiutil ditto mv; do
    ln -s "$root/test-install.sh" "$temporary_directory/bin/$command"
done

export FLOWMUX_INSTALL_MOCK=1
export TEST_LOG="$temporary_directory/commands.log"
PATH="$temporary_directory/bin:$PATH"
export PATH

TEST_ARCHITECTURE=amd64 sh "$root/install.sh" > "$temporary_directory/output"
grep -F 'curl https://github.com/flowmux-ai/flowmux/releases/download/v9.8.7/flowmux_9.8.7_amd64.deb' "$TEST_LOG" >/dev/null
grep -F 'apt-get update' "$TEST_LOG" >/dev/null
grep -F 'apt-get install -y ' "$TEST_LOG" | grep -F '/flowmux_9.8.7_amd64.deb' >/dev/null

: > "$TEST_LOG"
if TEST_ARCHITECTURE=arm64 sh "$root/install.sh" > /dev/null 2> "$temporary_directory/error"; then
    echo 'error: unsupported architecture was accepted' >&2
    exit 1
fi
grep -F "unsupported architecture 'arm64'" "$temporary_directory/error" >/dev/null
[ ! -s "$TEST_LOG" ]

# Ubuntu must also stop before apt on a checksum mismatch.
: > "$TEST_LOG"
if TEST_BAD_CHECKSUM=1 sh "$root/install.sh" > /dev/null 2> "$temporary_directory/error"; then
    echo 'error: Linux checksum mismatch was accepted' >&2
    exit 1
fi
! grep -F 'apt-get' "$TEST_LOG"

export TEST_OS=Darwin TEST_ARCHITECTURE=arm64
export FLOWMUX_MACOS_APP_DIR="$temporary_directory/My Apps"
export FLOWMUX_MACOS_BIN_DIR="$temporary_directory/My Bin"

: > "$TEST_LOG"
TEST_MISSING_LIBRARY=vte3 sh "$root/install.sh" > "$temporary_directory/output"
grep -F 'flowmux-9.8.7-aarch64-apple-darwin.dmg' "$TEST_LOG" >/dev/null
grep -F 'brew install vte3' "$TEST_LOG" >/dev/null
! grep -F 'apt-get' "$TEST_LOG"
grep -F 'hdiutil detach ' "$TEST_LOG" >/dev/null
[ "$(cat "$FLOWMUX_MACOS_APP_DIR/Flowmux.app/Contents/MacOS/flowmux")" = 'new app' ]
[ "$(readlink "$FLOWMUX_MACOS_BIN_DIR/flowmux")" = "$FLOWMUX_MACOS_APP_DIR/Flowmux.app/Contents/MacOS/flowmux" ]
[ -L "$FLOWMUX_MACOS_BIN_DIR/flowmuxctl" ]

# Every failure must preserve an existing installation.
printf 'previous app' > "$FLOWMUX_MACOS_APP_DIR/Flowmux.app/Contents/MacOS/flowmux"
for setting in TEST_RUNNING=1 TEST_RUNNING=2 TEST_BAD_CHECKSUM=1 TEST_MISSING_ASSET=1 TEST_BAD_SIGNATURE=1 TEST_FAIL_APP_MOVE=1 TEST_ARCHITECTURE=x86_64; do
    : > "$TEST_LOG"
    if env "$setting" sh "$root/install.sh" > /dev/null 2> "$temporary_directory/error"; then
        echo "error: failure accepted: $setting" >&2
        exit 1
    fi
    [ "$(cat "$FLOWMUX_MACOS_APP_DIR/Flowmux.app/Contents/MacOS/flowmux")" = 'previous app' ]
    case "$setting" in
        TEST_RUNNING=*|TEST_ARCHITECTURE=*) ! grep -F 'curl ' "$TEST_LOG" ;;
        TEST_BAD_CHECKSUM=*|TEST_MISSING_ASSET=*) ! grep -F 'hdiutil attach' "$TEST_LOG" ;;
        TEST_BAD_SIGNATURE=*) ! grep -F 'brew install' "$TEST_LOG" ;;
    esac
    echo "preservation test passed: $setting"
done

echo 'Linux and macOS installer tests passed'
