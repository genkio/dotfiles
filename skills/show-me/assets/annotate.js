;(() => {
  if (window.__showMeNotes) return
  window.__showMeNotes = true
  if (location.protocol === 'file:') { location.replace(new URL(document.currentScript.src).origin + location.pathname); return }

  const NOTES_URL = location.pathname.replace(/\.html?$/i, '') + '.notes.json'
  const BLOCK_SEL = 'h1,h2,h3,h4,p,li,tr,pre,blockquote,dt,dd,figcaption,.step,.keybox,.card'
  const POLL_MS = 2000

  const state = {
    data: { version: 1, threads: [] }, etag: '"0"',
    blocks: new Map(), order: [], sections: new Map(),
    composing: null, editing: null, attaching: null, focus: null,
    drafts: new Map(), open: localStorage.getItem('sm-open') !== '0',
  }

  const css = `
  :root{--sm-w:360px;--sm-accent:#1f5fa9;--sm-ink:#101418;--sm-ink2:#454f5b;--sm-ink3:#6b7684;--sm-line:#e3e7ec;--sm-bg:#fff;--sm-wait:#8a5a00;--sm-wait-bg:#fdf6e8;--sm-ok:#1b6b45;--sm-ok-bg:#eef6f1;--sm-tint:rgba(31,95,169,.07)}
  html.sm-open body{padding-right:calc(var(--sm-w) + 16px)}
  @media (max-width:960px){html.sm-open body{padding-right:0}}
  .sm-ui,.sm-ui *{box-sizing:border-box;font:14px/1.5 -apple-system,BlinkMacSystemFont,"Segoe UI","Hiragino Sans",Meiryo,sans-serif;color:var(--sm-ink)}
  .sm-ui textarea{width:100%;min-height:64px;resize:vertical;border:1px solid var(--sm-line);border-radius:6px;padding:8px 10px;background:#fbfcfd}
  .sm-ui textarea:focus{outline:2px solid var(--sm-accent);outline-offset:-1px;background:#fff}
  .sm-ui button{border:1px solid var(--sm-line);background:#fff;border-radius:6px;padding:4px 10px;cursor:pointer;font-size:13px;color:var(--sm-ink2)}
  .sm-ui button:hover{border-color:var(--sm-accent);color:var(--sm-accent)}
  .sm-ui button.sm-primary{background:var(--sm-accent);border-color:var(--sm-accent);color:#fff}
  .sm-ui button.sm-link{border:none;padding:2px 4px;font-size:12px;color:var(--sm-ink3)}
  .sm-ui button.sm-link:hover{color:var(--sm-accent)}
  .sm-ui code{background:#eef1f4;border-radius:4px;padding:1px 5px;font:12.5px ui-monospace,SFMono-Regular,Menlo,monospace}
  .sm-ui pre{background:#f5f7f9;border:1px solid var(--sm-line);border-radius:6px;padding:8px 10px;overflow:auto;font:12.5px/1.45 ui-monospace,SFMono-Regular,Menlo,monospace;white-space:pre-wrap}
  .sm-panel{position:fixed;top:0;right:0;bottom:0;width:var(--sm-w);background:var(--sm-bg);border-left:1px solid var(--sm-line);box-shadow:-8px 0 24px rgba(16,20,24,.05);display:flex;flex-direction:column;z-index:9998}
  @media (max-width:960px){.sm-panel{width:min(100vw,420px)}}
  html:not(.sm-open) .sm-panel{display:none}
  .sm-head{padding:14px 16px 10px;border-bottom:1px solid var(--sm-line);display:flex;align-items:center;gap:10px}
  .sm-head h3{margin:0;font-size:15px;font-weight:600;flex:1}
  .sm-head .sm-count{color:var(--sm-ink3);font-size:12px}
  .sm-hint{padding:8px 16px;font-size:12px;color:var(--sm-ink3);border-bottom:1px solid var(--sm-line);background:#fbfcfd}
  .sm-hint b{color:var(--sm-wait);font-weight:600}
  .sm-list{flex:1;overflow:auto;padding:12px 12px 40px}
  .sm-empty{color:var(--sm-ink3);font-size:13px;padding:24px 8px;text-align:center}
  .sm-sec{font-size:11px;text-transform:uppercase;letter-spacing:.06em;color:var(--sm-ink3);margin:14px 4px 6px;font-weight:600}
  .sm-card{border:1px solid var(--sm-line);border-radius:8px;padding:10px 12px;margin-bottom:10px;background:#fff}
  .sm-card.sm-focus{border-color:var(--sm-accent);box-shadow:0 0 0 2px rgba(31,95,169,.15)}
  .sm-card.sm-resolved{opacity:.7}
  .sm-quote{font-size:12px;color:var(--sm-ink3);border-left:3px solid var(--sm-line);padding:2px 8px;margin:0 0 8px;cursor:pointer;display:-webkit-box;-webkit-line-clamp:3;-webkit-box-orient:vertical;overflow:hidden}
  .sm-quote:hover{border-color:var(--sm-accent);color:var(--sm-ink2)}
  .sm-quote small{display:block;color:var(--sm-ink3);font-size:11px}
  .sm-row{display:flex;align-items:center;gap:6px;flex-wrap:wrap}
  .sm-pill{font-size:10.5px;font-weight:700;letter-spacing:.05em;text-transform:uppercase;padding:2px 8px;border-radius:999px;border:1px solid var(--sm-line);color:var(--sm-ink3)}
  .sm-pill.wait{background:var(--sm-wait-bg);color:var(--sm-wait);border-color:#f0e0bc}
  .sm-pill.done{background:var(--sm-ok-bg);color:var(--sm-ok);border-color:#c6e2d3}
  .sm-pill.agent{background:#eef3fa;color:var(--sm-accent);border-color:#cddcf0}
  .sm-msg{padding:8px 0;border-top:1px solid var(--sm-line)}
  .sm-msg:first-of-type{border-top:none}
  .sm-msg .sm-by{font-size:12px;color:var(--sm-ink3);display:flex;gap:8px;align-items:center}
  .sm-msg .sm-by b{color:var(--sm-ink);font-weight:600}
  .sm-msg .sm-by b.agent{color:var(--sm-accent)}
  .sm-msg .sm-tools{margin-left:auto;opacity:0;transition:opacity .12s}
  .sm-msg:hover .sm-tools{opacity:1}
  .sm-msg .sm-text{margin-top:3px;color:var(--sm-ink2);word-wrap:break-word}
  .sm-msg .sm-text p{margin:0 0 6px}
  .sm-msg .sm-text strong{color:var(--sm-ink)}
  .sm-actions{display:flex;gap:6px;margin-top:8px;align-items:center}
  .sm-actions .sm-spacer{flex:1}
  .sm-reply{margin-top:8px}
  .sm-reply textarea{min-height:40px}
  .sm-reply:focus-within textarea{min-height:72px}
  .sm-tab{position:fixed;top:14px;right:14px;z-index:9997;padding:6px 12px;border-radius:999px;background:#fff;border:1px solid var(--sm-line);box-shadow:0 2px 8px rgba(16,20,24,.08);font-size:13px;cursor:pointer}
  html.sm-open .sm-tab{display:none}
  .sm-add{position:fixed;z-index:9996;width:24px;height:24px;border-radius:50%;background:var(--sm-accent);color:#fff;border:none;font-size:18px;line-height:22px;text-align:center;cursor:pointer;opacity:0;pointer-events:none;transition:opacity .1s;box-shadow:0 1px 4px rgba(16,20,24,.2);padding:0}
  .sm-add.on{opacity:1;pointer-events:auto}
  .sm-marks{position:absolute;top:0;left:0;width:0;height:0;z-index:9995}
  .sm-mark{position:absolute;min-width:20px;height:20px;padding:0 6px;border-radius:999px;background:var(--sm-accent);color:#fff;font:11px/20px -apple-system,sans-serif;font-weight:700;text-align:center;cursor:pointer;box-shadow:0 1px 3px rgba(16,20,24,.2)}
  .sm-mark.wait{background:var(--sm-wait)}
  .sm-mark.done{background:var(--sm-ink3)}
  [data-sm-block].sm-hover{outline:2px dashed rgba(31,95,169,.35);outline-offset:2px}
  [data-sm-block].sm-noted{background:var(--sm-tint)}
  [data-sm-block].sm-active{background:rgba(31,95,169,.16);transition:background .3s}
  html.sm-attaching [data-sm-block]{cursor:crosshair}
  `

  const el = (tag, attrs = {}, ...kids) => {
    const n = document.createElement(tag)
    for (const [k, v] of Object.entries(attrs)) {
      if (k === 'class') n.className = v
      else if (k.startsWith('on')) n.addEventListener(k.slice(2), v)
      else if (k === 'html') n.innerHTML = v
      else n.setAttribute(k, v)
    }
    for (const k of kids.flat()) if (k != null) n.append(k)
    return n
  }
  const esc = (s) => s.replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]))
  const md = (s) => esc(s).split('```').map((p, i) => i % 2
    ? `<pre>${p.replace(/^[\w-]*\n/, '')}</pre>`
    : p.replace(/`([^`\n]+)`/g, '<code>$1</code>').replace(/\*\*([^*\n]+)\*\*/g, '<strong>$1</strong>')
      .split(/\n{2,}/).map((para) => `<p>${para.replace(/\n/g, '<br>')}</p>`).join('')).join('')
  const hash = (s) => { let h = 2166136261; for (const c of s) { h ^= c.codePointAt(0); h = Math.imul(h, 16777619) } return (h >>> 0).toString(16).padStart(8, '0') }
  const norm = (n) => n.textContent.replace(/\s+/g, ' ').trim()
  const uid = (p) => p + '-' + Math.random().toString(36).slice(2, 8)
  const ago = (iso) => {
    const s = Math.max(0, (Date.now() - Date.parse(iso)) / 1000)
    if (s < 60) return 'now'; if (s < 3600) return `${Math.floor(s / 60)}m`
    if (s < 86400) return `${Math.floor(s / 3600)}h`; return `${Math.floor(s / 86400)}d`
  }

  const tagBlocks = () => {
    state.blocks.clear(); state.order = []; state.sections.clear()
    const seen = new Map()
    let section = ''
    for (const n of document.querySelectorAll(BLOCK_SEL)) {
      if (n.closest('.sm-ui')) continue
      if (n.querySelector(BLOCK_SEL)) continue
      const text = norm(n)
      if (!text) continue
      if (/^H[12]$/.test(n.tagName)) section = text
      const base = `${n.tagName.toLowerCase()}:${hash(text)}`
      const c = (seen.get(base) || 0) + 1
      seen.set(base, c)
      const id = c > 1 ? `${base}#${c}` : base
      n.dataset.smBlock = id
      state.blocks.set(id, n); state.order.push(id); state.sections.set(id, section)
    }
  }

  const anchorFor = (id) => {
    const n = state.blocks.get(id)
    return { block: id, quote: norm(n).slice(0, 240), section: state.sections.get(id) || '' }
  }
  const lastBy = (t) => t.messages[t.messages.length - 1]?.by
  const statusOf = (t) => t.status === 'resolved' ? 'done' : lastBy(t) === 'user' ? 'wait' : 'agent'

  const load = async () => {
    const r = await fetch(NOTES_URL, { headers: { 'If-None-Match': state.etag }, cache: 'no-store' })
    if (r.status === 304) return false
    if (!r.ok) throw new Error(`notes ${r.status}`)
    state.data = await r.json(); state.etag = r.headers.get('ETag') || '"0"'
    state.data.threads ||= []
    return true
  }
  const mutate = async (fn) => {
    for (let i = 0; i < 4; i++) {
      await load().catch(() => {})
      const data = JSON.parse(JSON.stringify(state.data))
      data.version = 1; data.page = location.pathname.split('/').pop()
      fn(data)
      const r = await fetch(NOTES_URL, { method: 'PUT', headers: { 'If-Match': state.etag, 'Content-Type': 'application/json' }, body: JSON.stringify(data, null, 2) })
      if (r.status === 409) { state.etag = '"0"'; continue }
      if (!r.ok) throw new Error(`save ${r.status}`)
      state.data = data; state.etag = r.headers.get('ETag') || '"0"'
      render(); return
    }
    alert('Could not save notes (conflict). Reload and retry.')
  }

  const ui = {}
  const setOpen = (v) => { state.open = v; localStorage.setItem('sm-open', v ? '1' : '0'); document.documentElement.classList.toggle('sm-open', v); placeMarks() }
  const focusThread = (tid) => {
    state.focus = tid; setOpen(true); render()
    const t = state.data.threads.find((x) => x.id === tid)
    const n = t && state.blocks.get(t.anchor?.block)
    if (n) { n.scrollIntoView({ block: 'center', behavior: 'smooth' }); n.classList.add('sm-active'); setTimeout(() => n.classList.remove('sm-active'), 1400) }
    ui.list.querySelector(`[data-tid="${tid}"]`)?.scrollIntoView({ block: 'nearest', behavior: 'smooth' })
  }

  const textarea = (key, attrs, onSubmit) => {
    const ta = el('textarea', { ...attrs, 'data-draft': key, oninput: (e) => state.drafts.set(key, e.target.value),
      onkeydown: (e) => {
        if ((e.metaKey || e.ctrlKey) && e.key === 'Enter') { e.preventDefault(); onSubmit() }
        if (e.key === 'Escape') { state.composing = null; state.editing = null; state.drafts.delete(key); render() }
      } })
    ta.value = state.drafts.get(key) ?? attrs.value ?? ''
    return ta
  }

  const submitNew = () => {
    const bid = state.composing, text = (state.drafts.get('new') || '').trim()
    if (!bid || !text) return
    const anchor = anchorFor(bid)
    state.drafts.delete('new'); state.composing = null
    const id = uid('t')
    mutate((d) => d.threads.push({ id, anchor, status: 'open', createdAt: new Date().toISOString(),
      messages: [{ id: uid('m'), by: 'user', at: new Date().toISOString(), text }] })).then(() => { state.focus = id; render() })
  }
  const submitReply = (tid) => {
    const key = `reply:${tid}`, text = (state.drafts.get(key) || '').trim()
    if (!text) return
    state.drafts.delete(key)
    mutate((d) => { const t = d.threads.find((x) => x.id === tid); if (!t) return
      t.messages.push({ id: uid('m'), by: 'user', at: new Date().toISOString(), text }); t.status = 'open' })
  }
  const submitEdit = (tid, mid) => {
    const key = `edit:${mid}`, text = (state.drafts.get(key) || '').trim()
    state.editing = null; state.drafts.delete(key)
    if (!text) return render()
    mutate((d) => { const m = d.threads.find((x) => x.id === tid)?.messages.find((x) => x.id === mid)
      if (m && m.text !== text) { m.text = text; m.editedAt = new Date().toISOString() } })
  }
  const deleteMsg = (tid, mid) => mutate((d) => {
    const t = d.threads.find((x) => x.id === tid); if (!t) return
    t.messages = t.messages.filter((m) => m.id !== mid)
    if (!t.messages.length) d.threads = d.threads.filter((x) => x.id !== tid)
  })
  const deleteThread = (tid) => { if (confirm('Delete this whole thread?')) mutate((d) => { d.threads = d.threads.filter((x) => x.id !== tid) }) }
  const toggleResolve = (tid) => mutate((d) => { const t = d.threads.find((x) => x.id === tid); if (t) t.status = t.status === 'resolved' ? 'open' : 'resolved' })
  const reattach = (tid, bid) => { state.attaching = null; document.documentElement.classList.remove('sm-attaching')
    mutate((d) => { const t = d.threads.find((x) => x.id === tid); if (t) t.anchor = anchorFor(bid) }) }

  const quoteEl = (t, detached) => el('div', { class: 'sm-quote', title: t.anchor?.quote || '', onclick: () => !detached && focusThread(t.id) },
    t.anchor?.section && t.anchor.section !== t.anchor.quote ? el('small', {}, t.anchor.section) : null, t.anchor?.quote || '(no anchor)')

  const msgEl = (t, m) => {
    const editing = state.editing === m.id
    return el('div', { class: 'sm-msg' },
      el('div', { class: 'sm-by' }, el('b', { class: m.by }, m.by === 'agent' ? 'Agent' : 'You'), el('span', {}, ago(m.at) + (m.editedAt ? ' · edited' : '')),
        editing ? null : el('span', { class: 'sm-tools' },
          el('button', { class: 'sm-link', onclick: () => { state.editing = m.id; state.drafts.set(`edit:${m.id}`, m.text); render() } }, 'edit'),
          el('button', { class: 'sm-link', onclick: () => deleteMsg(t.id, m.id) }, 'delete'))),
      editing
        ? el('div', { class: 'sm-reply' }, textarea(`edit:${m.id}`, {}, () => submitEdit(t.id, m.id)),
          el('div', { class: 'sm-actions' }, el('button', { class: 'sm-primary', onclick: () => submitEdit(t.id, m.id) }, 'Save'),
            el('button', { onclick: () => { state.editing = null; state.drafts.delete(`edit:${m.id}`); render() } }, 'Cancel')))
        : el('div', { class: 'sm-text', html: md(m.text) }))
  }

  const cardEl = (t, detached) => {
    const st = statusOf(t)
    const pill = st === 'wait' ? ['wait', 'waiting for agent'] : st === 'done' ? ['done', 'resolved'] : ['agent', 'Agent replied']
    return el('div', { class: `sm-card${state.focus === t.id ? ' sm-focus' : ''}${t.status === 'resolved' ? ' sm-resolved' : ''}`, 'data-tid': t.id },
      quoteEl(t, detached),
      el('div', { class: 'sm-row' }, el('span', { class: `sm-pill ${pill[0]}` }, pill[1]),
        detached ? el('button', { class: 'sm-link', onclick: () => { state.attaching = t.id; document.documentElement.classList.add('sm-attaching') } },
          state.attaching === t.id ? 'click a block…' : 'attach to block…') : null),
      el('div', {}, t.messages.map((m) => msgEl(t, m))),
      el('div', { class: 'sm-reply' }, textarea(`reply:${t.id}`, { placeholder: 'Reply… (⌘↵ to send)' }, () => submitReply(t.id)),
        el('div', { class: 'sm-actions' }, el('button', { class: 'sm-primary', onclick: () => submitReply(t.id) }, 'Reply'),
          el('button', { onclick: () => toggleResolve(t.id) }, t.status === 'resolved' ? 'Reopen' : 'Resolve'),
          el('span', { class: 'sm-spacer' }), el('button', { class: 'sm-link', onclick: () => deleteThread(t.id) }, 'delete thread'))))
  }

  const composerEl = () => {
    const a = anchorFor(state.composing)
    return el('div', { class: 'sm-card sm-focus' }, quoteEl({ anchor: a }, true),
      textarea('new', { placeholder: 'Your note… (⌘↵ to save)', autofocus: 'autofocus' }, submitNew),
      el('div', { class: 'sm-actions' }, el('button', { class: 'sm-primary', onclick: submitNew }, 'Add note'),
        el('button', { onclick: () => { state.composing = null; state.drafts.delete('new'); render() } }, 'Cancel')))
  }

  const render = () => {
    const active = document.activeElement, key = active?.dataset?.draft, sel = key ? [active.selectionStart, active.selectionEnd] : null
    const threads = state.data.threads
    const idx = (t) => { const i = state.order.indexOf(t.anchor?.block); return i < 0 ? Infinity : i }
    const attached = threads.filter((t) => state.blocks.has(t.anchor?.block)).sort((a, b) => idx(a) - idx(b))
    const detached = threads.filter((t) => !state.blocks.has(t.anchor?.block))
    const waiting = threads.filter((t) => statusOf(t) === 'wait').length
    ui.count.textContent = `${threads.length} thread${threads.length === 1 ? '' : 's'}`
    ui.hint.innerHTML = waiting ? `<b>${waiting} waiting</b> · ask the agent: <code>/show-me reply</code>` : 'Hover any block and press <b style="color:var(--sm-accent)">+</b> to start a thread.'
    ui.tab.textContent = `Notes${threads.length ? ` (${threads.length}${waiting ? `, ${waiting} waiting` : ''})` : ''}`
    ui.list.replaceChildren(...[
      state.composing ? composerEl() : null,
      !threads.length && !state.composing ? el('div', { class: 'sm-empty' }, 'No notes yet.') : null,
      attached.map((t) => cardEl(t, false)),
      detached.length ? el('div', { class: 'sm-sec' }, 'Detached (block changed)') : null,
      detached.map((t) => cardEl(t, true)),
    ].flat().filter(Boolean))
    for (const n of state.blocks.values()) n.classList.remove('sm-noted')
    for (const t of attached) state.blocks.get(t.anchor.block).classList.add('sm-noted')
    if (key) { const ta = ui.list.querySelector(`[data-draft="${key}"]`); if (ta) { ta.focus(); ta.setSelectionRange(...sel) } }
    else if (state.composing) ui.list.querySelector('[data-draft="new"]')?.focus()
    placeMarks()
  }

  const placeMarks = () => {
    ui.marks.replaceChildren()
    if (!state.data.threads.length) return
    const byBlock = new Map()
    for (const t of state.data.threads) { if (!state.blocks.has(t.anchor?.block)) continue; (byBlock.get(t.anchor.block) || byBlock.set(t.anchor.block, []).get(t.anchor.block)).push(t) }
    for (const [bid, ts] of byBlock) {
      const r = state.blocks.get(bid).getBoundingClientRect()
      const worst = ts.some((t) => statusOf(t) === 'wait') ? 'wait' : ts.every((t) => statusOf(t) === 'done') ? 'done' : ''
      ui.marks.append(el('div', { class: `sm-mark ${worst}`, title: `${ts.length} note${ts.length > 1 ? 's' : ''}`,
        style: `top:${r.top + scrollY - 8}px;left:${r.right + scrollX - 14}px`, onclick: () => focusThread(ts[0].id) }, String(ts.length)))
    }
  }

  const mount = () => {
    document.head.append(el('style', {}, css))
    ui.marks = el('div', { class: 'sm-ui sm-marks' })
    ui.add = el('button', { class: 'sm-ui sm-add', title: 'Add note', html: '+' })
    ui.tab = el('button', { class: 'sm-ui sm-tab', onclick: () => setOpen(true) }, 'Notes')
    ui.count = el('span', { class: 'sm-count' })
    ui.hint = el('div', { class: 'sm-hint' })
    ui.list = el('div', { class: 'sm-list' })
    ui.panel = el('aside', { class: 'sm-ui sm-panel' },
      el('div', { class: 'sm-head' }, el('h3', {}, 'Notes'), ui.count, el('button', { class: 'sm-link', title: 'Hide panel', onclick: () => setOpen(false) }, '✕')),
      ui.hint, ui.list)
    document.body.append(ui.marks, ui.add, ui.tab, ui.panel)
    document.documentElement.classList.toggle('sm-open', state.open)

    let hover = null, hideTimer
    ui.add.addEventListener('mouseenter', () => clearTimeout(hideTimer))
    ui.add.addEventListener('click', () => { if (!hover) return; state.composing = hover.dataset.smBlock; state.drafts.delete('new'); setOpen(true); render() })
    document.addEventListener('mouseover', (e) => {
      const b = e.target.closest?.('[data-sm-block]')
      if (!b || b.closest('.sm-ui')) return
      clearTimeout(hideTimer)
      hover?.classList.remove('sm-hover'); hover = b; b.classList.add('sm-hover')
      const r = b.getBoundingClientRect()
      const left = Math.min(r.right + 6, innerWidth - (state.open && innerWidth > 960 ? 360 : 0) - 30)
      ui.add.style.top = `${Math.max(4, r.top)}px`; ui.add.style.left = `${Math.max(4, left)}px`; ui.add.classList.add('on')
    })
    document.addEventListener('mouseout', (e) => {
      const b = e.target.closest?.('[data-sm-block]'); if (!b || b !== hover) return
      hideTimer = setTimeout(() => { hover?.classList.remove('sm-hover'); hover = null; ui.add.classList.remove('on') }, 350)
    })
    document.addEventListener('click', (e) => {
      if (!state.attaching) return
      const b = e.target.closest?.('[data-sm-block]')
      if (b && !b.closest('.sm-ui')) { e.preventDefault(); reattach(state.attaching, b.dataset.smBlock) }
    }, true)
    document.addEventListener('keydown', (e) => { if (e.key === 'Escape' && state.attaching) { state.attaching = null; document.documentElement.classList.remove('sm-attaching'); render() } })
    addEventListener('resize', placeMarks)
    new ResizeObserver(placeMarks).observe(document.body)
  }

  const start = async () => {
    tagBlocks(); mount()
    try { await load() } catch (e) { ui.hint.textContent = `Notes unavailable: ${e.message}. Open this page through the show-me server.` }
    render()
    setInterval(async () => {
      if (state.editing || state.composing) return
      try { if (await load()) render() } catch {}
    }, POLL_MS)
  }
  document.readyState === 'loading' ? addEventListener('DOMContentLoaded', start) : start()
})()
