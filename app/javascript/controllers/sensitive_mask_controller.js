import { Controller } from "@hotwired/stimulus"

// Privacy-mode text masking. Singleton controller mounted on <body>.
//
// Walks every `.sensitive` element and replaces every character in its text
// nodes with `•` (including spaces and punctuation — no structure leaks).
// Leading/trailing whitespace is preserved so inline layout stays intact.
// Original text is cached on the text node so we can restore on toggle-off.
//
// `.sensitive--strong` (JSON viewers / payloads) is skipped — CSS blur owns it.
// Hover reveal was removed deliberately — privacy mode should be all-or-nothing
// when on, otherwise sensitive content leaks during a screen-share simply by
// the cursor passing over it.

const FORMATTERS = {
  default: (s) => {
    const lead  = s.match(/^\s*/)[0]
    const trail = s.match(/\s*$/)[0]
    const body  = s.slice(lead.length, s.length - trail.length)
    return lead + "•".repeat(body.length) + trail
  }
}

export default class extends Controller {
  connect() {
    this.onMutations = this.onMutations.bind(this)
    this.onClassChange = this.onClassChange.bind(this)

    this.bodyObserver = new MutationObserver(this.onMutations)
    this.bodyObserver.observe(document.body, { childList: true, subtree: true })

    this.htmlObserver = new MutationObserver(this.onClassChange)
    this.htmlObserver.observe(document.documentElement, { attributes: true, attributeFilter: ["class"] })

    this.sync()
  }

  disconnect() {
    this.bodyObserver?.disconnect()
    this.htmlObserver?.disconnect()
  }

  get isOn() {
    return document.documentElement.classList.contains("privacy-mode")
  }

  sync() {
    const on = this.isOn
    this.eachTarget((el) => on ? this.mask(el) : this.unmask(el))
  }

  onClassChange() { this.sync() }

  onMutations(records) {
    if (!this.isOn) return
    for (const r of records) {
      r.addedNodes.forEach((n) => {
        if (n.nodeType !== 1) return
        if (this.isTarget(n)) this.mask(n)
        n.querySelectorAll?.(".sensitive:not(.sensitive--strong)").forEach((el) => this.mask(el))
      })
    }
  }

  eachTarget(fn) {
    document.querySelectorAll(".sensitive:not(.sensitive--strong)").forEach(fn)
  }

  isTarget(el) {
    return el.classList?.contains("sensitive") && !el.classList.contains("sensitive--strong")
  }

  mask(el) {
    if (el.dataset.masked === "1") return
    const fmt = FORMATTERS[el.dataset.maskFormat] ?? FORMATTERS.default
    this.walkOwnText(el, (node) => {
      if (!node.nodeValue || !node.nodeValue.trim()) return
      if (node.__realText == null) node.__realText = node.nodeValue
      node.nodeValue = fmt(node.__realText)
    })
    el.dataset.masked = "1"
  }

  unmask(el) {
    if (el.dataset.masked !== "1") return
    this.walkOwnText(el, (node) => {
      if (node.__realText != null) node.nodeValue = node.__realText
    })
    delete el.dataset.masked
  }

  // Walk text nodes whose closest .sensitive ancestor is `root` — avoids
  // double-masking when .sensitive elements are nested.
  walkOwnText(root, fn) {
    const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
      acceptNode: (node) => {
        const owner = node.parentElement?.closest(".sensitive")
        return owner === root ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_REJECT
      }
    })
    let n
    while ((n = walker.nextNode())) fn(n)
  }
}
