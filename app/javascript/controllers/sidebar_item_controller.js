import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["submenu", "chevron"]
  static values = { open: Boolean }

  connect() {
    this.update()
  }

  toggle() {
    this.openValue = !this.openValue
  }

  openValueChanged() {
    this.update()
  }

  update() {
    if (this.hasSubmenuTarget) {
      if (this.openValue) {
        this.submenuTarget.classList.remove("hidden")
      } else {
        this.submenuTarget.classList.add("hidden")
      }
    }
    if (this.hasChevronTarget) {
      if (this.openValue) {
        this.chevronTarget.classList.remove("-rotate-90")
      } else {
        this.chevronTarget.classList.add("-rotate-90")
      }
    }
  }
}
