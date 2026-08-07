#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later

set -eu

if [ "${FLOWMUX_INSTALL_MOCK:-}" = 1 ]; then
    case ${0##*/} in
        uname)
            echo Linux
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
                *.deb.sha256)
                    package_path=${output%.sha256}
                    package=${package_path##*/}
                    directory=${package_path%/*}
                    (cd "$directory" && sha256sum "$package" > "$package.sha256")
                    ;;
                *.deb)
                    : > "$output"
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

for command in uname dpkg curl apt-get sudo; do
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

echo 'installer test passed'
