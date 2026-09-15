#!/usr/bin/env node
// CLI for the agent to read/answer show-me notes safely (atomic write, no hand-edited JSON).
//   notes.mjs list  <page.html|page.notes.json> [--all]
//   notes.mjs reply <page> <threadId> [text]        text from arg or stdin
//   notes.mjs resolve <page> <threadId>
import fs from 'node:fs'
import path from 'node:path'

const [cmd, target, ...rest] = process.argv.slice(2)
if (!cmd || !target) { console.error('usage: notes.mjs list|reply|resolve <page> [threadId] [text]'); process.exit(2) }

const file = target.endsWith('.notes.json') ? target : target.replace(/\.html?$/i, '') + '.notes.json'
const read = () => fs.existsSync(file) ? JSON.parse(fs.readFileSync(file, 'utf8')) : { version: 1, threads: [] }
const write = (d) => { const tmp = `${file}.${process.pid}.tmp`; fs.writeFileSync(tmp, JSON.stringify(d, null, 2) + '\n'); fs.renameSync(tmp, file) }
const lastBy = (t) => t.messages[t.messages.length - 1]?.by
const pending = (t) => t.status !== 'resolved' && lastBy(t) === 'user'
const readStdin = () => fs.readFileSync(0, 'utf8')

const data = read()
if (cmd === 'list') {
  const all = rest.includes('--all')
  const ts = data.threads.filter((t) => all || pending(t))
  if (!ts.length) { console.log(all ? 'no threads' : 'no pending threads'); process.exit(0) }
  for (const t of ts) {
    const tag = t.status === 'resolved' ? 'resolved' : pending(t) ? 'PENDING' : 'answered'
    console.log(`\n== ${t.id} [${tag}] ${t.anchor?.section ? `§ ${t.anchor.section} ` : ''}`)
    console.log(`   > ${t.anchor?.quote || '(detached)'}`)
    for (const m of t.messages) console.log(`   ${m.by === 'agent' ? 'agent ' : 'user  '}: ${m.text.replace(/\n/g, '\n           ')}`)
  }
} else if (cmd === 'reply') {
  const [tid, ...words] = rest
  const t = data.threads.find((x) => x.id === tid)
  if (!t) { console.error(`no thread ${tid}`); process.exit(1) }
  const text = (words.length ? words.join(' ') : readStdin()).trim()
  if (!text) { console.error('empty reply'); process.exit(1) }
  t.messages.push({ id: 'm-' + Math.random().toString(36).slice(2, 8), by: 'agent', at: new Date().toISOString(), text })
  write(data); console.log(`replied ${tid}`)
} else if (cmd === 'resolve') {
  const t = data.threads.find((x) => x.id === rest[0])
  if (!t) { console.error(`no thread ${rest[0]}`); process.exit(1) }
  t.status = 'resolved'; write(data); console.log(`resolved ${t.id}`)
} else { console.error(`unknown command ${cmd}`); process.exit(2) }
