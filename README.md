# Flowmux website

Static landing page for [Flowmux](https://github.com/flowmux-ai/flowmux-terminal).

## Local preview

```sh
python3 -m http.server 4173
```

Open `http://localhost:4173`.

## Deployment

Pushes to `main` deploy to GitHub Pages through `.github/workflows/pages.yml`.
The production URL is `https://flowmux-ai.github.io/flowmux.github.io/` until a custom domain is configured.
