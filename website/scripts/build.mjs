import { cp, mkdir, readFile, readdir, rm, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { createHash } from 'node:crypto';

const root = fileURLToPath(new URL('..', import.meta.url));
const dist = path.join(root, 'dist');
// Only these public assets ship. Documentation, screenshots, provider metadata
// and local credentials are not part of the deployed static directory.
const assets = [
  'index.html', 'styles.css', 'app.js', 'tokens.css',
  'design-system.html', 'system.css', 'system.js', '404.html', '_headers', 'videos.json', 'locale.js',
  'zh/index.html', 'zh/design-system.html', 'zh/404.html',
];
const mediaExtensions = new Set(['.mp4', '.webm', '.png', '.jpg', '.jpeg', '.webp', '.avif', '.vtt']);
async function collectMedia(relative = 'media') {
  const entries = await readdir(path.join(root, relative), { withFileTypes: true });
  for (const entry of entries) {
    const file = path.posix.join(relative, entry.name);
    if (entry.isDirectory()) await collectMedia(file);
    else if (entry.isFile() && mediaExtensions.has(path.extname(entry.name).toLowerCase())) assets.push(file);
  }
}
await collectMedia();
const sources = new Map(await Promise.all(assets.filter(file => !file.startsWith('media/')).map(async file => [file, await readFile(path.join(root, file), 'utf8')])));
// Keep each page and its styles/scripts on the same revision, including CSS
// imports. A cached stylesheet must not style a newer page's header structure.
const hash = createHash('sha256');
for (const [file, source] of sources) {
  hash.update(file).update('\0').update(source).update('\0');
}
const version = hash.digest('hex').slice(0, 12);
function versionedAsset(url, owner) {
  const file = url.split('?')[0];
  const resolved = file.startsWith('/') ? file.slice(1) : path.posix.join(path.posix.dirname(owner), file);
  return sources.has(resolved) ? `${file}?v=${version}` : url;
}
function renderAsset(file, source) {
  if (file.endsWith('.html')) return source.replace(/((?:href|src)=")([^"?#]+\.(?:css|js))(?:\?[^"#]*)?(")/g,
    (_, before, url, after) => before + versionedAsset(url, file) + after);
  if (file.endsWith('.css')) return source.replace(/(@import\s+url\(['"]?)([^'"\)]+)(['"]?\))/g,
    (_, before, url, after) => before + versionedAsset(url, file) + after);
  return source;
}
await mkdir(dist, { recursive: true });
// Keep the watched directory alive for Wrangler when rebuilding the preview.
const published = new Set([...assets, 'robots.txt']);
async function prune(relative = '') {
  for (const entry of await readdir(path.join(dist, relative), { withFileTypes: true })) {
    const file = path.posix.join(relative, entry.name);
    if (entry.isDirectory() && [...published].some(asset => asset.startsWith(`${file}/`))) await prune(file);
    else if (!entry.isFile() || !published.has(file)) await rm(path.join(dist, file), { recursive: true, force: true });
  }
}
await prune();
for (const file of assets) {
  await mkdir(path.dirname(path.join(dist, file)), { recursive: true });
  if (sources.has(file)) await writeFile(path.join(dist, file), renderAsset(file, sources.get(file)));
  else await cp(path.join(root, file), path.join(dist, file));
}
await writeFile(path.join(dist, 'robots.txt'), 'User-agent: *\nAllow: /\n');
console.log(`Built ${assets.length + 1} public assets in ${dist}`);
