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

## Deployment

Pushes to `main` deploy to GitHub Pages through `.github/workflows/pages.yml`.
The workflow tests the installer before publishing it. The production URL is
`https://flowmux.org/`.
