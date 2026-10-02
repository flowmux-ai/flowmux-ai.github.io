import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import vm from "node:vm";

const html = await readFile(new URL("index.html", import.meta.url), "utf8");
const script = html.match(/<script id="install-count-script">([\s\S]*?)<\/script>/)[1];
const initialCount = html.match(/<strong id="install-count"[^>]*>([^<]*)/)[1];
const asset = (name, download_count) => ({ name, download_count });
const count = { textContent: initialCount, removeAttribute(name) { delete this[name]; } };
const pages = [
  [{ assets: [asset("flowmux.deb", 32), asset("flowmux.tar.gz", 63),
    asset("flowmux.deb.sha256", 78), asset("overview.png", 2)] },
  ...Array.from({ length: 99 }, () => ({ assets: [] }))],
  [{ assets: [asset("flowmux.dmg", 1000)] }],
];
let requests = [];
let failPage = 0;
let refresh;
const document = { hidden: false, getElementById: () => count };
const context = vm.createContext({
  document, AbortSignal,
  fetch: async (url) => {
    requests.push(url);
    const page = Number(new URL(url).searchParams.get("page"));
    return { ok: page !== failPage, json: async () => pages[page - 1] };
  },
  setInterval: (callback, delay) => {
    assert.equal(delay, 300000);
    refresh = callback;
  },
});

vm.runInContext(script, context);
await new Promise(setImmediate);
assert.equal(count.textContent, "1,095", "Count packages across all pages, excluding checksums and images");
assert.equal(requests.length, 2);
assert.ok(requests[1].endsWith("per_page=100&page=2"));

failPage = 2;
await vm.runInContext("refreshInstallCount()", context);
assert.equal(count.textContent, "1,095", "Never replace a complete count with a partial total");
assert.ok(count.title);

count.textContent = initialCount;
failPage = 1;
await vm.runInContext("refreshInstallCount()", context);
assert.equal(count.textContent, initialCount, "Keep the build snapshot when the first API request fails");

failPage = 0;
pages[0] = [{ assets: [asset("flowmux.deb", -1)] }];
await vm.runInContext("refreshInstallCount()", context);
assert.equal(count.textContent, initialCount, "Reject invalid counts");

pages[0] = [];
await vm.runInContext("refreshInstallCount()", context);
assert.equal(count.textContent, "0");
assert.equal(count.title, undefined, "Clear the unavailable notice after recovery");

requests = [];
document.hidden = true;
refresh();
assert.equal(requests.length, 0, "Do not poll in background tabs");
document.hidden = false;
refresh();
await new Promise(setImmediate);
assert.equal(requests.length, 1, "Refresh visible pages");
console.log("Install count checks passed.");
