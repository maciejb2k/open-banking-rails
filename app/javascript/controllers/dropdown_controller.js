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
    const menuW = this._menu.offsetWidth
    const menuH = this._menu.offsetHeight
    const margin = 8
    const vw = window.innerWidth
    const vh = window.innerHeight

    // Default: bottom-end (right edge aligned to trigger right). Clamp into
    // the viewport with an 8px margin so the menu never bleeds off-screen
    // on narrow phones.
    let left = rect.right - menuW
    let top = rect.bottom + 4
    if (left < margin) left = margin
    if (left + menuW > vw - margin) left = vw - menuW - margin
    // Flip above the trigger when there isn't enough room below.
    if (top + menuH > vh - margin && rect.top - menuH - 4 > margin) {
      top = rect.top - menuH - 4
    }

    this._menu.style.position = "fixed"
    this._menu.style.top = `${top}px`
    this._menu.style.left = `${left}px`
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
