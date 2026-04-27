import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["trigger", "selected", "dropdown", "hidden"]
  static values = { options: Array, selected: Array, fieldName: String }

  connect() {
    this.selectedValues = new Set(this.selectedValue.map(String))
    this.boundClose = this.closeOnOutside.bind(this)
    this.renderSelected()
    this.renderHidden()
    this.renderDropdown()
  }

  disconnect() {
    document.removeEventListener("click", this.boundClose, true)
  }

  toggle() {
    this.dropdownTarget.classList.contains("hidden") ? this.open() : this.close()
  }

  open() {
    this.renderDropdown()
    this.dropdownTarget.classList.remove("hidden")
    document.addEventListener("click", this.boundClose, true)
  }

  close() {
    this.dropdownTarget.classList.add("hidden")
    document.removeEventListener("click", this.boundClose, true)
  }

  select(event) {
    const value = String(event.currentTarget.dataset.value)
    this.selectedValues.has(value) ? this.selectedValues.delete(value) : this.selectedValues.add(value)
    this.renderSelected()
    this.renderHidden()
    this.renderDropdown()
  }

  remove(event) {
    event.stopPropagation()
    this.selectedValues.delete(String(event.currentTarget.dataset.value))
    this.renderSelected()
    this.renderHidden()
    this.renderDropdown()
  }

  renderSelected() {
    const selected = this.optionsValue.filter(o => this.selectedValues.has(String(o.value)))
    this.selectedTarget.innerHTML = selected.length
      ? selected.map(o => `
          <span class="inline-flex items-center gap-1 rounded-full bg-primary/10 px-2 py-0.5 text-xs font-medium text-primary">
            ${o.label}
            <button type="button"
                    data-action="click->multi-select#remove"
                    data-value="${o.value}"
                    class="hover:text-primary/70 transition-colors leading-none">×</button>
          </span>
        `).join("")
      : `<span class="text-muted-foreground text-sm">${this.element.dataset.placeholder || "Select options..."}</span>`
  }

  renderHidden() {
    this.hiddenTarget.innerHTML = [...this.selectedValues]
      .map(v => `<input type="hidden" name="${this.fieldNameValue}" value="${v}">`)
      .join("")
  }

  renderDropdown() {
    this.dropdownTarget.innerHTML = this.optionsValue.length
      ? this.optionsValue.map(o => {
          const active = this.selectedValues.has(String(o.value))
          return `
            <button type="button"
                    class="w-full text-left px-3 py-2 text-sm flex items-center gap-2 transition-colors ${active ? "bg-primary/10 text-primary" : "hover:bg-muted/50"}"
                    data-action="click->multi-select#select"
                    data-value="${o.value}">
              <span class="w-4 shrink-0 text-center">${active ? "✓" : ""}</span>
              ${o.label}
            </button>
          `
        }).join("")
      : `<p class="px-3 py-2 text-sm text-muted-foreground">No options available.</p>`
  }

  closeOnOutside(event) {
    if (!this.element.contains(event.target)) this.close()
  }
}
