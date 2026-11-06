import { cp, mkdir, readdir, readFile, stat, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { resolve } from 'node:path';
import { renderPage } from '../src/page.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
const preview = process.env.VERCEL_ENV === 'preview';
const deploymentOrigin = process.env.VERCEL_URL ? 'https://' + process.env.VERCEL_URL : '';
const configuredOrigin = (preview ? deploymentOrigin : process.env.SITE_URL || deploymentOrigin);
let origin = '';
if (configuredOrigin) {
  const url = new URL(configuredOrigin);
  if (url.protocol !== 'https:' || url.username || url.password || url.pathname !== '/' || url.search || url.hash) {
    throw new Error('SITE_URL must be a public HTTPS origin without a path or credentials');
  }
  origin = url.origin;
}
const html = renderPage({ origin, preview });
const ids = [...html.matchAll(/\sid="([^"]+)"/g)].map((match) => match[1]);
if (new Set(ids).size !== ids.length) throw new Error('Duplicate IDs in the page');
for (const [, path] of html.matchAll(/\s(?:href|src)="([^"]+)"/g)) {
  if (path.startsWith('#') && !ids.includes(path.slice(1))) throw new Error('Missing anchor ' + path);
  if (path.startsWith('/assets/')) await stat(resolve(root, path.slice(1)));
  if (!/^(#|\/|https:\/\/|mailto:)/.test(path)) throw new Error('Unsupported link ' + path);
}
for (const match of html.matchAll(/<img\b[^>]*>/g)) {
  for (const attr of ['alt', 'width', 'height']) {
    if (!match[0].includes(' ' + attr + '="')) throw new Error('Image missing ' + attr);
  }
}
const assets = await readdir(resolve(root, 'assets'));
for (const path of new Set(html.match(/\/assets\/[\w.-]+/g))) {
  if (!assets.includes(path.slice('/assets/'.length))) throw new Error('Missing asset ' + path);
}
const css = await readFile(resolve(root, 'src/styles.css'), 'utf8');
if (!css.includes('prefers-reduced-motion') || !css.includes(':focus-visible')) {
  throw new Error('Required accessibility styles are missing');
}
if (!process.argv.includes('--check')) {
  await mkdir(resolve(root, 'dist'), { recursive: true });
  await cp(resolve(root, 'assets'), resolve(root, 'dist/assets'), { recursive: true });
  await writeFile(resolve(root, 'dist/index.html'), html);
  await writeFile(resolve(root, 'dist/styles.css'), css);
  console.log('Built dist/index.html, styles and assets');
}
console.log('Checked anchors, asset references, image attributes and accessibility styles');
