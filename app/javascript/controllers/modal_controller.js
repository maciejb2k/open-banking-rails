import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.boundEscape = this.onEscape.bind(this)
    document.addEventListener("keydown", this.boundEscape)
  }

  disconnect() {
    document.removeEventListener("keydown", this.boundEscape)
  }

  open() {
    this.element.classList.remove("hidden")
    document.body.classList.add("overflow-hidden")
  }

  close() {
    this.element.classList.add("hidden")
    document.body.classList.remove("overflow-hidden")
  }

  onEscape(event) {
    if (event.key === "Escape") this.close()
  }
}
