import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["search", "dropdown", "hidden"]
  static values = { options: Array }

  connect() {
    this.boundClose = this.closeOnOutside.bind(this)
    this.render(this.optionsValue)
    // Populate the visible search input from the existing hidden value
    // so editing a record shows the current selection by label, not blank.
    this.restoreLabel()
  }

  clear() {
    this.hiddenTarget.value = ""
    this.searchTarget.value = ""
    this.render(this.optionsValue)
  }

  // On focus we wipe the visible input so the user can start typing
  // immediately. The hidden value is preserved — if the user closes
  // without picking, restoreLabel() puts the previous label back.
  focus() {
    this.searchTarget.value = ""
    this.render(this.optionsValue)
    this.open()
  }

  open() {
    this.dropdownTarget.classList.remove("hidden")
    document.addEventListener("click", this.boundClose, true)
  }

  close() {
    this.dropdownTarget.classList.add("hidden")
    document.removeEventListener("click", this.boundClose, true)
  }

  filter() {
    const q = this.searchTarget.value.toLowerCase()
    const filtered = this.optionsValue.filter(o => o.label.toLowerCase().includes(q))
    this.render(filtered)
    this.open()
  }

  select(event) {
    const value = event.currentTarget.dataset.value
    const label = event.currentTarget.dataset.label
    this.hiddenTarget.value = value
    this.searchTarget.value = label
    this.close()
  }

  render(options) {
    this.dropdownTarget.innerHTML = options.map(o => `
      <button type="button"
              data-action="click->searchable-select#select"
              data-value="${o.value}" data-label="${o.label}"
              class="w-full text-left px-3 py-2 text-sm hover:bg-muted/50 transition-colors ${this.hiddenTarget.value === String(o.value) ? "bg-primary/10 text-primary" : ""}">
        ${o.label}
      </button>
    `).join("") || `<p class="px-3 py-2 text-sm text-muted-foreground">No results</p>`
  }

  closeOnOutside(event) {
    if (!this.element.contains(event.target)) {
      this.restoreLabel()
      this.close()
    }
  }

  restoreLabel() {
    const current = this.hiddenTarget.value
    if (current) {
      const match = this.optionsValue.find(o => String(o.value) === String(current))
      if (match) this.searchTarget.value = match.label
    } else {
      this.searchTarget.value = ""
    }
  }

  disconnect() {
    document.removeEventListener("click", this.boundClose, true)
  }
}
