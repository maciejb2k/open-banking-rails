import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["toast"]
  static values = { timeout: { type: Number, default: 0 } }

  connect() {
    if (this.timeoutValue > 0) {
      this.timer = setTimeout(() => this.dismiss(), this.timeoutValue)
    }
  }

  disconnect() {
    clearTimeout(this.timer)
  }

  dismiss() {
    this.element.style.opacity = "0"
    this.element.style.transition = "opacity 300ms"
    setTimeout(() => this.element.remove(), 300)
  }
}
