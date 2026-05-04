import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { source: String, copiedLabel: { type: String, default: "Copied!" } }
  static targets = ["button"]

  copy(event) {
    event.preventDefault()
    const text = this.sourceValue
    if (!text) return

    if (navigator.clipboard && window.isSecureContext) {
      navigator.clipboard.writeText(text).then(() => this.flash())
    } else {
      // navigator.clipboard requires HTTPS; this runs on plain-http dev origins.
      const ta = document.createElement("textarea")
      ta.value = text
      ta.style.position = "fixed"
      ta.style.opacity = "0"
      document.body.appendChild(ta)
      ta.select()
      try { document.execCommand("copy") } finally { document.body.removeChild(ta) }
      this.flash()
    }
  }

  flash() {
    if (!this.hasButtonTarget) return
    const btn = this.buttonTarget
    const original = btn.innerText
    btn.innerText = this.copiedLabelValue
    setTimeout(() => { btn.innerText = original }, 1500)
  }
}
