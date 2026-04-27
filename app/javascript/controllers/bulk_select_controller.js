import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["checkbox", "all", "bar", "count"]

  toggleAll() {
    const checked = this.allTarget.checked
    this.checkboxTargets.forEach(cb => { cb.checked = checked })
    this.update()
  }

  toggle() {
    this.update()
    if (this.hasAllTarget) {
      this.allTarget.checked = this.checkboxTargets.every(cb => cb.checked)
    }
  }

  update() {
    const count = this.checkboxTargets.filter(cb => cb.checked).length
    if (this.hasBarTarget) {
      this.barTarget.classList.toggle("hidden", count === 0)
    }
    if (this.hasCountTarget) {
      this.countTarget.textContent = `${count} selected`
    }
  }
}
