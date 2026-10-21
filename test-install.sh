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
                https://flowmux.org/deferred-macos-app-swap.sh)
                    cp "$TEST_SWAP_HELPER" "$output"
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
            # apt lists missing dependencies and asks before installing them.
            if [ "$1" = install ]; then
                printf 'Install dependencies? [Y/n] '
                read -r answer
                case "$answer" in ""|y|Y|yes|YES) ;; *) exit 1 ;; esac
            fi
            printf 'apt-get' >> "$TEST_LOG"
            printf ' %s' "$@" >> "$TEST_LOG"
            printf '\n' >> "$TEST_LOG"
            ;;
        brew)
            printf 'brew %s\n' "$*" >> "$TEST_LOG"
            case "$1" in
                --prefix) echo /opt/homebrew ;;
                list) [ "${TEST_MISSING_LIBRARY:-}" != "$3" ] ;;
                install) [ "${TEST_BREW_FAIL:-0}" != 1 ] ;;
                *) exit 1 ;;
            esac
            ;;
        ps)
            if [ "${TEST_RUNNING:-0}" = 1 ]; then
                printf '424242 %s/Flowmux.app/Contents/MacOS/flowmux\n' "$FLOWMUX_MACOS_APP_DIR"
            elif [ "${TEST_RUNNING:-0}" = 2 ]; then
                printf '424242 %s/flowmux\n' "$FLOWMUX_MACOS_BIN_DIR"
            fi
            ;;
        launchctl)
            printf 'launchctl %s\n' "$*" >> "$TEST_LOG"
            [ "${TEST_LAUNCH_FAIL:-0}" != 1 ]
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

for command in uname dpkg curl apt-get sudo brew ps codesign hdiutil ditto mv launchctl; do
    ln -s "$root/test-install.sh" "$temporary_directory/bin/$command"
done

export HOME="$temporary_directory/home"
export TEST_SWAP_HELPER="$root/deferred-macos-app-swap.sh"
export FLOWMUX_INSTALL_MOCK=1
export TEST_LOG="$temporary_directory/commands.log"
PATH="$temporary_directory/bin:$PATH"
export PATH

# Give each mock installation a terminal and accept the default Y/n answer.
cat > "$temporary_directory/confirm.py" <<'PYCONFIRM'
import errno
import os
import pty
import select
import sys
import time

pid, terminal = pty.fork()
if pid == 0:
    os.execl("/bin/sh", "sh", sys.argv[1])
deadline = time.monotonic() + 15
output = b""
try:
    while time.monotonic() < deadline:
        if not select.select([terminal], [], [], 0.1)[0]:
            continue
        try:
            data = os.read(terminal, 8192)
        except OSError as error:
            if error.errno == errno.EIO:
                break
            raise
        if not data:
            break
        output += data
        if output.endswith(b"[Y/n] "):
            os.write(terminal, b"\n")
    else:
        os.kill(pid, 9)
        raise AssertionError("installer timed out")
finally:
    os.close(terminal)
    _, status = os.waitpid(pid, 0)
sys.stderr.buffer.write(output)
sys.exit(os.waitstatus_to_exitcode(status))
PYCONFIRM

TEST_ARCHITECTURE=amd64 python3 "$temporary_directory/confirm.py" "$root/install.sh" > "$temporary_directory/output"
grep -F 'curl https://github.com/flowmux-ai/flowmux/releases/download/v9.8.7/flowmux_9.8.7_amd64.deb' "$TEST_LOG" >/dev/null
grep -F 'apt-get update' "$TEST_LOG" >/dev/null
grep -F 'apt-get install ' "$TEST_LOG" | grep -F '/flowmux_9.8.7_amd64.deb' >/dev/null

: > "$TEST_LOG"
if TEST_ARCHITECTURE=arm64 python3 "$temporary_directory/confirm.py" "$root/install.sh" > /dev/null 2> "$temporary_directory/error"; then
    echo 'error: unsupported architecture was accepted' >&2
    exit 1
fi
grep -F "unsupported architecture 'arm64'" "$temporary_directory/error" >/dev/null
[ ! -s "$TEST_LOG" ]

# Ubuntu must also stop before apt on a checksum mismatch.
: > "$TEST_LOG"
if TEST_BAD_CHECKSUM=1 python3 "$temporary_directory/confirm.py" "$root/install.sh" > /dev/null 2> "$temporary_directory/error"; then
    echo 'error: Linux checksum mismatch was accepted' >&2
    exit 1
fi
! grep -F 'apt-get' "$TEST_LOG"

export TEST_OS=Darwin TEST_ARCHITECTURE=arm64
export FLOWMUX_MACOS_APP_DIR="$temporary_directory/My Apps"
export FLOWMUX_MACOS_BIN_DIR="$temporary_directory/My Bin"

: > "$TEST_LOG"
TEST_MISSING_LIBRARY=vte3 python3 "$temporary_directory/confirm.py" "$root/install.sh" > "$temporary_directory/output"
grep -F 'flowmux-9.8.7-aarch64-apple-darwin.dmg' "$TEST_LOG" >/dev/null
grep -F 'brew install vte3' "$TEST_LOG" >/dev/null
! grep -F 'apt-get' "$TEST_LOG"
grep -F 'hdiutil detach ' "$TEST_LOG" >/dev/null
[ "$(cat "$FLOWMUX_MACOS_APP_DIR/Flowmux.app/Contents/MacOS/flowmux")" = 'new app' ]
[ "$(readlink "$FLOWMUX_MACOS_BIN_DIR/flowmux")" = "$FLOWMUX_MACOS_APP_DIR/Flowmux.app/Contents/MacOS/flowmux" ]
[ -L "$FLOWMUX_MACOS_BIN_DIR/flowmuxctl" ]

# Every failure must preserve an existing installation.
printf 'previous app' > "$FLOWMUX_MACOS_APP_DIR/Flowmux.app/Contents/MacOS/flowmux"
for setting in TEST_BAD_CHECKSUM=1 TEST_MISSING_ASSET=1 TEST_BAD_SIGNATURE=1 TEST_FAIL_APP_MOVE=1 TEST_ARCHITECTURE=x86_64; do
    : > "$TEST_LOG"
    if env "$setting" python3 "$temporary_directory/confirm.py" "$root/install.sh" > /dev/null 2> "$temporary_directory/error"; then
        echo "error: failure accepted: $setting" >&2
        exit 1
    fi
    [ "$(cat "$FLOWMUX_MACOS_APP_DIR/Flowmux.app/Contents/MacOS/flowmux")" = 'previous app' ]
    case "$setting" in
        TEST_ARCHITECTURE=*) ! grep -F 'curl ' "$TEST_LOG" ;;
        TEST_BAD_CHECKSUM=*|TEST_MISSING_ASSET=*) ! grep -F 'hdiutil attach' "$TEST_LOG" ;;
        TEST_BAD_SIGNATURE=*) ! grep -F 'brew install' "$TEST_LOG" ;;
    esac
    echo "preservation test passed: $setting"
done

# Running apps keep their current bundle while a verified update is staged.
for running in 1 2; do
    : > "$TEST_LOG"
    TEST_RUNNING=$running python3 "$temporary_directory/confirm.py" "$root/install.sh" > "$temporary_directory/output" 2>&1
    [ "$(cat "$FLOWMUX_MACOS_APP_DIR/Flowmux.app/Contents/MacOS/flowmux")" = 'previous app' ]
    [ "$(cat "$FLOWMUX_MACOS_APP_DIR/.Flowmux.app.pending.424242/Contents/MacOS/flowmux")" = 'new app' ]
    grep -F 'launchctl submit' "$TEST_LOG" >/dev/null
    grep -F 'Quit Flowmux when convenient' "$temporary_directory/output" >/dev/null
    grep -F 'hdiutil detach' "$TEST_LOG" >/dev/null
    rm -rf "$FLOWMUX_MACOS_APP_DIR/.Flowmux.app.pending.424242"
done
if TEST_RUNNING=1 TEST_LAUNCH_FAIL=1 python3 "$temporary_directory/confirm.py" "$root/install.sh" > /dev/null 2> "$temporary_directory/error"; then
    echo 'error: failed update scheduling was accepted' >&2
    exit 1
fi
[ "$(cat "$FLOWMUX_MACOS_APP_DIR/Flowmux.app/Contents/MacOS/flowmux")" = 'previous app' ]
grep -F 'could not schedule update' "$temporary_directory/error" >/dev/null

echo 'Linux and macOS installer tests passed'

# Exercise the actual curl-style pipe with a separate controlling terminal.
python3 - "$root/install.sh" <<'PYTEST'
import errno
import os
import pty
import select
import shlex
import subprocess
import sys
import time
from pathlib import Path

installer = sys.argv[1]
log = Path(os.environ["TEST_LOG"])
app = Path(os.environ["FLOWMUX_MACOS_APP_DIR"]) / "Flowmux.app/Contents/MacOS/flowmux"
for system in ["Linux", "Darwin"]:
    os.environ.update(TEST_OS=system, TEST_ARCHITECTURE="amd64" if system == "Linux" else "arm64",
                      TEST_MISSING_LIBRARY="vte3")
    for answer in [b"n\n", b"\n", b"y\n"]:
        log.write_text("")
        app.write_text("previous app")
        pid, terminal = pty.fork()
        if pid == 0:
            os.execl("/bin/sh", "sh", "-c", "cat " + shlex.quote(installer) + " | sh")
        output = b""
        answered = False
        deadline = time.monotonic() + 15
        try:
            while time.monotonic() < deadline:
                if not select.select([terminal], [], [], 0.1)[0]:
                    continue
                try:
                    data = os.read(terminal, 8192)
                except OSError as error:
                    if error.errno == errno.EIO:
                        break
                    raise
                if not data:
                    break
                output += data
                if b"[Y/n]" in output and not answered:
                    os.write(terminal, answer)
                    answered = True
            else:
                os.kill(pid, 9)
                raise AssertionError("confirmation timed out: " + repr(output))
        finally:
            os.close(terminal)
            _, status = os.waitpid(pid, 0)
        assert answered, output
        calls = log.read_text()
        install_command = "apt-get install" if system == "Linux" else "brew install vte3"
        if answer != b"n\n":
            assert os.waitstatus_to_exitcode(status) == 0, output
            assert install_command in calls, calls
        else:
            assert os.waitstatus_to_exitcode(status) != 0, output
            assert install_command not in calls, calls
            assert app.read_text() == "previous app"
    log.write_text("")
    result = subprocess.run(["sh", installer], stdin=subprocess.DEVNULL, capture_output=True,
                            start_new_session=True, timeout=15)
    assert result.returncode != 0 and b"requires a terminal" in result.stderr, result.stderr
    assert "brew install" not in log.read_text() and "apt-get" not in log.read_text()

log.write_text("")
app.write_text("previous app")
result = subprocess.run([sys.executable, str(Path(os.environ["TEST_LOG"]).parent / "confirm.py"), installer], env=dict(os.environ, TEST_BREW_FAIL="1"),
                        capture_output=True, timeout=15)
assert result.returncode != 0
assert app.read_text() == "previous app"
assert "hdiutil detach" in log.read_text()
print("Piped installer consent, refusal, unattended, and dependency failure tests passed")
PYTEST

# The real helper must wait for every host and restore the app if a move fails.
python3 - "$root/deferred-macos-app-swap.sh" <<'PYSWAP'
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time

helper = sys.argv[1]
with tempfile.TemporaryDirectory(prefix="flowmux-swap-") as directory:
    root = Path(directory)
    app = root / "Flowmux.app"
    pending = root / ".Flowmux.app.pending.123"
    backup = root / ".Flowmux.app.previous.123"
    app.mkdir()
    pending.mkdir()
    (app / "version").write_text("old")
    (pending / "version").write_text("new")
    processes = [subprocess.Popen(["/bin/sleep", "30"]) for _ in range(2)]
    swap = subprocess.Popen(["sh", helper, "\n".join(str(p.pid) for p in processes),
                             str(pending), str(app), str(backup)])
    try:
        time.sleep(0.3)
        assert swap.poll() is None and (app / "version").read_text() == "old"
        processes[0].terminate()
        processes[0].wait(timeout=5)
        time.sleep(0.3)
        assert swap.poll() is None and (app / "version").read_text() == "old"
        processes[1].terminate()
        processes[1].wait(timeout=5)
        assert swap.wait(timeout=5) == 0
        assert (app / "version").read_text() == "new" and not backup.exists()
    finally:
        for process in processes + [swap]:
            if process.poll() is None:
                process.terminate()
            process.wait(timeout=5)
    pending.mkdir()
    (pending / "version").write_text("failed update")
    stubs = root / "bin"
    stubs.mkdir()
    (stubs / "mv").write_text('#!/bin/sh\ncase "$1" in *.pending.123) exit 1 ;; esac\nexec /bin/mv "$@"\n')
    (stubs / "mv").chmod(0o755)
    result = subprocess.run(["sh", helper, str(processes[0].pid), str(pending), str(app), str(backup)],
                            env=dict(os.environ, PATH=str(stubs) + ":" + os.environ["PATH"]),
                            capture_output=True, timeout=5)
    assert b"could not install" in result.stderr
    assert (app / "version").read_text() == "new" and pending.exists()
print("DEFERRED_APP_SWAP_OK: waits for all hosts and restores failed replacement")
PYSWAP
