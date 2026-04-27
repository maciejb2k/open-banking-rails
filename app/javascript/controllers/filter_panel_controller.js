import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["panel", "overlay"]

  connect() {
    this.form = this.element.querySelector("form")
    if (this.form) {
      this.form.addEventListener("submit", this.#stripBlankParams)
    }
  }

  disconnect() {
    if (this.form) {
      this.form.removeEventListener("submit", this.#stripBlankParams)
    }
  }

  open() {
    this.panelTarget.classList.remove("translate-x-full")
    this.panelTarget.classList.add("translate-x-0")
    this.overlayTarget.classList.remove("hidden")
    document.body.style.overflow = "hidden"
  }

  close() {
    this.panelTarget.classList.remove("translate-x-0")
    this.panelTarget.classList.add("translate-x-full")
    this.overlayTarget.classList.add("hidden")
    document.body.style.overflow = ""
  }

  #stripBlankParams = () => {
    // Disable all empty non-checkbox inputs (includes hidden fields like q[s])
    this.form.querySelectorAll("input:not([type=checkbox]):not([type=radio]), select:not([multiple])").forEach(el => {
      if (el.value === "") el.disabled = true
    })

    // Checkboxes: always disable Rails' companion hidden "0" field;
    // also disable the checkbox itself when unchecked
    this.form.querySelectorAll("input[type=checkbox]").forEach(checkbox => {
      const prev = checkbox.previousElementSibling
      if (prev?.type === "hidden" && prev.name === checkbox.name) {
        prev.disabled = true
      }
      if (!checkbox.checked) checkbox.disabled = true
    })

    // Multi-selects: disable when nothing is selected (also disables Rails' companion hidden)
    this.form.querySelectorAll("select[multiple]").forEach(select => {
      if ([...select.options].every(o => !o.selected)) {
        select.disabled = true
        const prev = select.previousElementSibling
        if (prev?.type === "hidden" && prev.name === select.name) {
          prev.disabled = true
        }
      }
    })
  }
}
