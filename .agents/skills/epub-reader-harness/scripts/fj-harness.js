// SPDX-License-Identifier: GPL-2.0-or-later
//
// foliate-js harness glue: plays the GTK side of Foliate 3.3 for its own,
// unmodified reader/reader.html + reader/reader.js (extracted from the
// flatpak).  Loaded from reader/harness.html, a copy of reader.html with
// this script added before reader.js (the page's CSP only allows 'self'
// scripts, so no inline code).
//
// Query: book=<url>, at=<href|cfi> (start location, "EPUB/text/ch005.xhtml"
// style hrefs), and Foliate view settings: cols, gap, maxInlineSize,
// maxBlockSize, flow (paginated|scrolled), animated, lineHeight, justify,
// hyphenate, overrideFont (0/1 for booleans), css (user stylesheet).
// Exposes window.harnessEvents (messages reader.js sends to GTK), the
// window.harness helpers below, and sets document.title = 'ready' once the
// first page is laid out.

const params = new URLSearchParams(location.search)
const num = (k, d) => params.has(k) ? Number(params.get(k)) : d
const bool = (k, d) => params.has(k) ? params.get(k) === '1' : d

// Foliate 3.3 gschema defaults.
const layout = {
    gap: num('gap', 0.06), maxInlineSize: num('maxInlineSize', 720),
    maxBlockSize: num('maxBlockSize', 1440), maxColumnCount: num('cols', 2),
    flow: params.get('flow') ?? 'paginated', animated: bool('animated', true),
}
const style = {
    lineHeight: num('lineHeight', 1.5), justify: bool('justify', true),
    hyphenate: bool('hyphenate', true), invert: false,
    theme: {
        name: 'default',
        light: { fg: '#000000', bg: '#ffffff', link: '#0066cc' },
        dark: { fg: '#e0e0e0', bg: '#222222', link: '#77bbee' },
    },
    overrideFont: bool('overrideFont', false), userStylesheet: params.get('css') ?? '',
}

const onBookReady = async () => {
    // Same order as Foliate's book-viewer.js: style first, then
    // dataStore.initView() -> view.init({ lastLocation }).
    await globalThis.reader.setAppearance({ style, layout, autohideCursor: false })
    await globalThis.reader.view.init({ lastLocation: params.get('at') })
    document.title = 'ready'
}

globalThis.harnessEvents = []
globalThis.webkit = { messageHandlers: { viewer: { postMessage: s => {
    const m = JSON.parse(s)
    globalThis.harnessEvents.push(m)
    if (m.type === 'ready') setTimeout(start)  // reader.js finishes evaluating first
    else if (m.type === 'book-ready') onBookReady().catch(e => { document.title = 'error: ' + e })
    else if (m.type === 'book-error') document.title = 'error: ' + (m.id ?? m.message)
} } } }
// The selection popover is a GTK widget in Foliate; resolve to "no action".
globalThis.showSelection = () => Promise.resolve(null)

const sleep = ms => new Promise(r => setTimeout(r, ms))

// Helpers for fj-eval.  Geometry: the paginator scrolls a container whose
// content starts one page (renderer.size) before the section iframe, so an
// element's iframe x plus renderer.size is comparable with renderer.start/
// end (the visible spread).  Horizontal LTR books only.
const visible = (r, b) => b.width > 0 && b.left + r.size >= r.start - 2 && b.left + r.size < r.end - 2

globalThis.harness = {
    get r() { return globalThis.reader.view.renderer },
    get doc() { return this.r.getContents()[0]?.doc },
    state() {
        const r = this.r, index = r.getContents()[0]?.index, loc = globalThis.reader.view.lastLocation
        return {
            section: index, href: globalThis.reader.book.sections[index]?.id,
            page: r.page, pages: r.pages, location: loc?.location, cfi: loc?.cfi,
            footnoteOpen: document.getElementById('footnote-dialog').open,
        }
    },
    // Elements matching sel that start in the visible spread and continue
    // past its end; overflowOnly keeps those wider than their own box.
    splitHere(sel = 'pre', overflowOnly = false) {
        const r = this.r, out = []
        this.doc.querySelectorAll(sel).forEach((e, i) => {
            const xs = [...e.getClientRects()].map(x => x.left + r.size)
            const here = xs.filter(x => x >= r.start - 2 && x < r.end - 2).length
            if (xs.length > 1 && here && xs.some(x => x >= r.end - 2)
                && (!overflowOnly || e.scrollWidth > e.clientWidth))
                out.push({ i, fragments: xs.length, scrollWidth: e.scrollWidth,
                    clientWidth: e.clientWidth, overflow: getComputedStyle(e).overflowX,
                    text: e.textContent.trim().slice(0, 60) })
        })
        return out
    },
    // Turn pages until splitHere() matches; stays on that spread.
    async findSplit(sel = 'pre', overflowOnly = false, max = 200) {
        for (let turns = 0; turns <= max; turns++) {
            const split = this.splitHere(sel, overflowOnly)
            if (split.length) return { turns, state: this.state(), split }
            await globalThis.reader.view.next()
            await sleep(150)
        }
        return null
    },
    // Visible links whose href contains pattern.
    links(pattern = '') {
        const r = this.r
        return [...this.doc.querySelectorAll('a[href]')]
            .filter(a => a.getAttribute('href').includes(pattern) && visible(r, a.getBoundingClientRect()))
            .map(a => ({ href: a.getAttribute('href'), text: a.textContent.trim().slice(0, 40) }))
    },
    // Turn pages until a link whose href contains pattern is visible.
    async findLink(pattern, max = 200) {
        for (let turns = 0; turns <= max; turns++) {
            const links = this.links(pattern)
            if (links.length) return { turns, state: this.state(), links }
            await globalThis.reader.view.next()
            await sleep(150)
        }
        return null
    },
    // Click the first visible link whose href contains pattern (and whose
    // text contains text, if given), through foliate-js's own handler:
    // noteref links open the footnote dialog, others navigate.
    async clickLink(pattern, text = '') {
        const r = this.r
        const a = [...this.doc.querySelectorAll('a[href]')]
            .find(a => a.getAttribute('href').includes(pattern) && a.textContent.includes(text)
                && visible(r, a.getBoundingClientRect()))
        if (!a) return null
        a.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true, view: this.doc.defaultView }))
        await sleep(800)
        const dlg = document.getElementById('footnote-dialog')
        return { href: a.getAttribute('href'), footnoteOpen: dlg.open,
            footnoteType: dlg.querySelector('header').innerText, state: this.state() }
    },
    closeFootnote() { document.getElementById('footnote-dialog').close(); return true },
    async turn(n = 1) {
        for (let i = 0; i < Math.abs(n); i++) await (n > 0 ? globalThis.reader.view.next() : globalThis.reader.view.prev())
        await sleep(300)
        return this.state()
    },
    async goTo(target) { await globalThis.reader.view.goTo(target); await sleep(300); return this.state() },
}

// reader.js posts 'ready', then Foliate calls init(), which clicks the
// hidden #file-input; hand it the book as a File instead of a chooser.
const start = async () => {
    const res = await fetch(params.get('book'))
    const file = new File([await res.blob()], 'book.epub', { type: 'application/epub+zip' })
    const input = document.getElementById('file-input')
    input.click = () => {
        const dt = new DataTransfer()
        dt.items.add(file)
        input.files = dt.files
        input.dispatchEvent(new Event('change'))
    }
    globalThis.init({ uiText: {
        loc: 'Loc. %s of %s', page: 'Page %s of %s', pageWithoutTotal: 'Page %s', close: 'Close',
        references: {
            footnote: 'Footnote', 'footnote-go': 'Go to Footnote',
            endnote: 'Endnote', 'endnote-go': 'Go to Endnote',
            note: 'Note', 'note-go': 'Go to Note',
            glossary: 'Definition', 'glossary-go': 'Go to Definition',
            biblioentry: 'Bibliography', 'biblioentry-go': 'Go to Bibliography',
        },
    } })
}
