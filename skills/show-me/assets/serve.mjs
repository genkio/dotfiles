import http from 'node:http'
import fs from 'node:fs'
import fsp from 'node:fs/promises'
import path from 'node:path'
import os from 'node:os'

const PORT = Number(process.env.SHOW_ME_PORT || 4747)
const HOME = os.homedir()
const ASSETS = path.dirname(new URL(import.meta.url).pathname)
const TYPES = {
  '.html': 'text/html; charset=utf-8', '.json': 'application/json; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8', '.mjs': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8', '.png': 'image/png', '.jpg': 'image/jpeg',
  '.svg': 'image/svg+xml', '.webp': 'image/webp', '.gif': 'image/gif',
}
const INJECT = '<script src="/_show-me/annotate.js"></script>'

const send = (res, code, body, headers = {}) => {
  res.writeHead(code, { 'Cache-Control': 'no-store', ...headers })
  res.end(body)
}

const etagOf = (st) => `"${Math.floor(st.mtimeMs)}-${st.size}"`

const localPath = (urlPath) => {
  const p = path.normalize(decodeURIComponent(urlPath))
  if (!p.startsWith(HOME + path.sep)) return null
  return p
}

const readBody = (req, limit = 2 * 1024 * 1024) => new Promise((resolve, reject) => {
  const chunks = []
  let size = 0
  req.on('data', (c) => {
    size += c.length
    if (size > limit) { reject(new Error('too large')); req.destroy() }
    chunks.push(c)
  })
  req.on('end', () => resolve(Buffer.concat(chunks).toString('utf8')))
  req.on('error', reject)
})

const serveNotes = async (req, res, file) => {
  let st
  try { st = await fsp.stat(file) } catch { return send(res, 200, '{"version":1,"threads":[]}', { 'Content-Type': TYPES['.json'], ETag: '"0"' }) }
  const etag = etagOf(st)
  if (req.headers['if-none-match'] === etag) return send(res, 304, '', { ETag: etag })
  send(res, 200, await fsp.readFile(file), { 'Content-Type': TYPES['.json'], ETag: etag })
}

const writeNotes = async (req, res, file) => {
  let etag = '"0"'
  try { etag = etagOf(await fsp.stat(file)) } catch {}
  const expected = req.headers['if-match']
  if (expected && expected !== etag) return send(res, 409, etag, { ETag: etag })
  const body = await readBody(req)
  try { JSON.parse(body) } catch { return send(res, 400, 'invalid json') }
  const tmp = `${file}.${process.pid}.tmp`
  await fsp.writeFile(tmp, body)
  await fsp.rename(tmp, file)
  send(res, 200, etagOf(await fsp.stat(file)), { ETag: etagOf(await fsp.stat(file)) })
}

const serveHtml = async (res, file) => {
  let html = await fsp.readFile(file, 'utf8')
  if (!html.includes('/_show-me/annotate.js')) {
    html = html.includes('</body>') ? html.replace('</body>', `${INJECT}\n</body>`) : html + INJECT
  }
  send(res, 200, html, { 'Content-Type': TYPES['.html'] })
}

const server = http.createServer(async (req, res) => {
  try {
    const url = new URL(req.url, 'http://localhost')
    if (url.pathname === '/_show-me/health') return send(res, 200, 'ok')
    if (url.pathname === '/_show-me/annotate.js') {
      return send(res, 200, await fsp.readFile(path.join(ASSETS, 'annotate.js')), { 'Content-Type': TYPES['.js'] })
    }
    const site = req.headers['sec-fetch-site']
    if (site && site !== 'same-origin' && site !== 'none') return send(res, 403, 'forbidden')
    const file = localPath(url.pathname)
    if (!file) return send(res, 403, 'outside home')
    const ext = path.extname(file).toLowerCase()
    if (file.endsWith('.notes.json')) {
      if (req.method === 'GET') return serveNotes(req, res, file)
      if (req.method === 'PUT') return writeNotes(req, res, file)
      return send(res, 405, 'method')
    }
    if (req.method !== 'GET' || !TYPES[ext]) return send(res, 404, 'not found')
    if (!fs.existsSync(file)) return send(res, 404, 'not found')
    if (ext === '.html') return serveHtml(res, file)
    send(res, 200, await fsp.readFile(file), { 'Content-Type': TYPES[ext] })
  } catch (e) {
    send(res, 500, String(e?.message || e))
  }
})

server.listen(PORT, '127.0.0.1', () => console.log(`show-me notes server on http://127.0.0.1:${PORT}`))
