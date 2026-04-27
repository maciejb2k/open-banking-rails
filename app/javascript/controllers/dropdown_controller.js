import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["menu"]

  connect() {
    this._menu = this.menuTarget
    this.boundClose = this.closeOnOutsideClick.bind(this)
    this.boundReposition = this.reposition.bind(this)
  }

  toggle() {
    const open = !this._menu.classList.contains("hidden")
    open ? this.close() : this.open()
  }

  open() {
    document.body.appendChild(this._menu)
    this._menu.classList.remove("hidden")
    this.reposition()
    document.addEventListener("click", this.boundClose, true)
    window.addEventListener("scroll", this.boundReposition, true)
    window.addEventListener("resize", this.boundReposition)
  }

  close() {
    this.element.appendChild(this._menu)
    this._menu.classList.add("hidden")
    document.removeEventListener("click", this.boundClose, true)
    window.removeEventListener("scroll", this.boundReposition, true)
    window.removeEventListener("resize", this.boundReposition)
  }

  reposition() {
    const trigger = this.element.querySelector("button")
    const rect = trigger.getBoundingClientRect()
    this._menu.style.position = "fixed"
    this._menu.style.top = `${rect.bottom + 4}px`
    this._menu.style.left = `${rect.right - this._menu.offsetWidth}px`
    this._menu.style.right = "auto"
  }

  closeOnOutsideClick(event) {
    if (!this.element.contains(event.target) && !this._menu.contains(event.target)) {
      this.close()
    }
  }

  disconnect() {
    if (!this._menu.classList.contains("hidden")) {
      this.close()
    }
  }
}
