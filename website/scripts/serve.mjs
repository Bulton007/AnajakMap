import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { extname, resolve, sep } from 'node:path';
import './build.mjs';

const root = fileURLToPath(new URL('../dist/', import.meta.url));
const types = { '.html': 'text/html; charset=utf-8', '.css': 'text/css; charset=utf-8', '.jpg': 'image/jpeg', '.png': 'image/png' };
const port = Number(process.env.PORT || 4173);
createServer(async (req, res) => {
  try {
    const pathname = decodeURIComponent(new URL(req.url, 'http://localhost').pathname);
    const file = resolve(root, pathname === '/' ? 'index.html' : '.' + pathname);
    if (!file.startsWith(resolve(root) + sep) || !types[extname(file)]) throw new Error('Unknown path');
    const bytes = await readFile(file);
    res.writeHead(200, { 'Content-Type': types[extname(file)], 'Content-Length': bytes.length });
    res.end(req.method === 'HEAD' ? undefined : bytes);
  } catch {
    res.writeHead(404);
    res.end('Not found');
  }
}).listen(port, '127.0.0.1', () => console.log('Local http://127.0.0.1:' + port));
