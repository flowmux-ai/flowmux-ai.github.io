# flowmux website

Static landing page for [flowmux](https://github.com/flowmux-ai/flowmux).

## Local preview

```sh
python3 -m http.server 4173
```

Open `http://localhost:4173`.

## Installer

`install.sh` is the POSIX shell installer served at
`https://flowmux.org/install.sh`. It resolves the latest flowmux GitHub
Release and verifies the selected asset's SHA-256 before installation:

- Ubuntu 24.04+ / amd64: installs `flowmux_VERSION_amd64.deb` with `apt`.
- macOS / Apple Silicon: mounts `flowmux-VERSION-aarch64-apple-darwin.dmg`
  read-only, verifies the app signature, installs missing `gtk4`, `libadwaita`,
  and `vte3` Homebrew libraries, and copies the app to `~/Applications`.
  Homebrew must already be installed at `/opt/homebrew`. CLI symlinks are
  created in `~/.local/bin`; add that directory to PATH if needed.

On macOS, `FLOWMUX_MACOS_APP_DIR` and `FLOWMUX_MACOS_BIN_DIR` override the
installation directories. Quit the destination app before updating; the
installer never terminates a running session. The app remains an ad-hoc-signed
preview without Developer ID signing or notarization; Gatekeeper may block it.
It is not a standalone app, and its in-app updater still builds from source.

The latest release must contain the platform asset and checksum. Until a
release with a macOS DMG is published, macOS installation stops with a missing
asset message before modifying the installed app. No source-build fallback
is used.

Run its isolated command-flow test with:

```sh
./test-install.sh
```

The installer sends no flowmux telemetry. GitHub maintains an aggregate count
for each downloaded release asset; it is a download count, not a unique-user
or successful-install count. Query all `.deb` counts with:

```sh
gh api repos/flowmux-ai/flowmux/releases --paginate \
  --jq '.[] | .tag_name as $tag | .assets[] | select(.name | endswith("_amd64.deb")) | [$tag, .name, .download_count] | @tsv'
```

## Install count

The homepage's “Downloads to date” counter sums program asset downloads across
all GitHub Releases, excluding checksums and images. Updates and repeat downloads
count; unique users and install success are not measured.

GitHub Actions collects all pages using the authenticated API and embeds the count
and actual collection time in the deployed HTML. The daily schedule is 08:00 KST
(23:00 UTC); pushes and manual deployments also refresh the snapshot. Scheduled
runs can be delayed, so “Last counted” shows the actual time in KST. Browsers do
not call the GitHub API. A failed API request or invalid count stops deployment,
leaving the previous published count and timestamp available.

Check asset filtering, KST timestamps, and failure handling with:

```sh
python3 test-install-count.py
```

## Deployment

Pushes to `main` deploy to GitHub Pages through `.github/workflows/pages.yml`.
The workflow tests the installer before publishing it. The production URL is
`https://flowmux.org/`.
