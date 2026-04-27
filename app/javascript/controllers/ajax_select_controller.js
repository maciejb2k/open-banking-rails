import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "dropdown", "hidden"]
  static values = { url: String, mockOptions: Array, minChars: Number, sortBy: String }

  connect() {
    this.debounceTimer = null
    this.boundClose = this.closeOnOutside.bind(this)
  }

  disconnect() {
    document.removeEventListener("click", this.boundClose, true)
  }

  search() {
    clearTimeout(this.debounceTimer)
    const q = this.inputTarget.value.trim()
    const minChars = this.hasMinCharsValue ? this.minCharsValue : 1
    if (q.length < minChars) { this.close(); return }
    if (this.hasMockOptionsValue) {
      const results = this.mockOptionsValue.filter(o => o.label.toLowerCase().includes(q.toLowerCase()))
      this.render(this.sort(results))
    } else {
      this.debounceTimer = setTimeout(() => this.fetch(q), 250)
    }
  }

  async fetch(q) {
    const url = `${this.urlValue}?q=${encodeURIComponent(q)}`
    const response = await fetch(url, {
      headers: { "Accept": "application/json", "X-Requested-With": "XMLHttpRequest" }
    })
    const results = await response.json()
    this.render(this.sort(results))
  }

  sort(results) {
    if (!this.hasSortByValue || !this.sortByValue) return results
    const field = this.sortByValue
    return [...results].sort((a, b) => String(a[field] ?? "").localeCompare(String(b[field] ?? "")))
  }

  render(results) {
    this.dropdownTarget.innerHTML = results.length
      ? results.map(r => `
          <button type="button"
                  class="w-full text-left px-3 py-2 text-sm hover:bg-muted/50 transition-colors"
                  data-action="click->ajax-select#select"
                  data-id="${r.id}" data-label="${r.label}">
            ${r.label}
          </button>
        `).join("")
      : `<p class="px-3 py-2 text-sm text-muted-foreground">No results found.</p>`
    this.open()
  }

  select(event) {
    const { id, label } = event.currentTarget.dataset
    this.hiddenTarget.value = id
    this.inputTarget.value = label
    this.close()
  }

  clear() {
    this.hiddenTarget.value = ""
    this.inputTarget.value = ""
    this.close()
  }

  open() {
    this.dropdownTarget.classList.remove("hidden")
    document.addEventListener("click", this.boundClose, true)
  }

  close() {
    this.dropdownTarget.classList.add("hidden")
    this.dropdownTarget.innerHTML = ""
    document.removeEventListener("click", this.boundClose, true)
  }

  closeOnOutside(event) {
    if (!this.element.contains(event.target)) this.close()
  }
}
