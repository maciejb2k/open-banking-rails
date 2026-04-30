import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["trigger", "selected", "dropdown", "hidden", "search"]
  static values = { options: Array, selected: Array, fieldName: String, cloakSelected: Boolean, searchable: Boolean }

  connect() {
    this.selectedValues = new Set(this.selectedValue.map(String))
    this.searchQuery = ""
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
    if (this.hasSearchTarget) this.searchTarget.focus()
  }

  close() {
    this.dropdownTarget.classList.add("hidden")
    document.removeEventListener("click", this.boundClose, true)
    this.searchQuery = ""
  }

  filter() {
    this.searchQuery = this.searchTarget.value.toLowerCase()
    this.renderDropdown({ keepSearchFocus: true })
  }

  select(event) {
    const value = String(event.currentTarget.dataset.value)
    this.selectedValues.has(value) ? this.selectedValues.delete(value) : this.selectedValues.add(value)
    this.renderSelected()
    this.renderHidden()
    this.renderDropdown({ keepSearchFocus: true })
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
    const cloak = this.cloakSelectedValue
    this.selectedTarget.innerHTML = selected.length
      ? selected.map(o => {
          // Always-on bullet mask when cloak is set — independent of the
          // topbar privacy_mode (which only flips .sensitive). Same UX as
          // the server-side hide_private_text helper.
          const labelHtml = cloak ? "•".repeat(Math.min(o.label.length, 24)) : o.label
          return `
            <span class="inline-flex items-center gap-1 rounded-full bg-primary/10 px-2 py-0.5 text-xs font-medium text-primary">
              ${labelHtml}
              <button type="button"
                      data-action="click->multi-select#remove"
                      data-value="${o.value}"
                      class="hover:text-primary/70 transition-colors leading-none">×</button>
            </span>
          `
        }).join("")
      : `<span class="text-muted-foreground text-sm">${this.element.dataset.placeholder || "Select options..."}</span>`
  }

  renderHidden() {
    this.hiddenTarget.innerHTML = [...this.selectedValues]
      .map(v => `<input type="hidden" name="${this.fieldNameValue}" value="${v}">`)
      .join("")
  }

  renderDropdown(opts = {}) {
    const q = this.searchQuery
    const filtered = q
      ? this.optionsValue.filter(o => o.label.toLowerCase().includes(q))
      : this.optionsValue

    const searchHeader = this.searchableValue
      ? `<div class="sticky top-0 bg-card border-b p-2 z-10">
           <input type="text"
                  data-multi-select-target="search"
                  data-action="input->multi-select#filter"
                  placeholder="Szukaj…"
                  value="${q || ""}"
                  class="form-input w-full text-sm">
         </div>`
      : ""

    const items = filtered.length
      ? filtered.map(o => {
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
      : `<p class="px-3 py-2 text-sm text-muted-foreground">${q ? "Brak wyników" : "No options available."}</p>`

    this.dropdownTarget.innerHTML = searchHeader + items

    if (opts.keepSearchFocus && this.hasSearchTarget) {
      this.searchTarget.focus()
      const len = this.searchTarget.value.length
      this.searchTarget.setSelectionRange(len, len)
    }
  }

  closeOnOutside(event) {
    if (!this.element.contains(event.target)) this.close()
  }
}
