import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["field", "show", "hide", "label"]
  static values = { onLabel: String, offLabel: String }

  connect() {
    if (this.hasLabelTarget) this.updateLabel()
  }

  switch() {
    if (!this.hasFieldTarget) return
    const input = this.fieldTarget
    const isPassword = input.type === "password" || input.type === "text"
    if (isPassword) {
      input.type = input.type === "password" ? "text" : "password"
      if (this.hasShowTarget) this.showTarget.classList.toggle("hidden")
      if (this.hasHideTarget) this.hideTarget.classList.toggle("hidden")
    }
  }

  update() {
    this.updateLabel()
  }

  updateLabel() {
    if (!this.hasLabelTarget || !this.hasFieldTarget) return
    const checked = this.fieldTarget.checked
    const onLabel = this.labelTarget.dataset.onLabel || "Enabled"
    const offLabel = this.labelTarget.dataset.offLabel || "Disabled"
    this.labelTarget.textContent = checked ? onLabel : offLabel
  }
}
