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
Release, downloads the `amd64` `.deb` and checksum, verifies SHA-256, then
installs the package with `apt` on supported Linux systems.

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

The homepage's “Install to date” counter sums program asset downloads across
all GitHub Releases, excluding checksums and images. It fetches the public
GitHub API on page load and every five minutes while the page is visible.
Updates and repeat downloads count; unique users and install success are not
measured. Each deployment embeds a fresh count using the authenticated GitHub
API. If the browser API fails or rate-limits the visitor, that snapshot or the
last successfully loaded count stays visible.

Check pagination, asset filtering, and failure handling with:

```sh
node test-install-count.mjs
```

## Deployment

Pushes to `main` deploy to GitHub Pages through `.github/workflows/pages.yml`.
The workflow tests the installer before publishing it. The production URL is
`https://flowmux.org/`.
