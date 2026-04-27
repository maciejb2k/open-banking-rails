import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "tags", "hidden"]

  connect() {
    this.tags = this.hiddenTarget.value ? this.hiddenTarget.value.split(",").filter(Boolean) : []
    this.render()
  }

  onKeydown(event) {
    if (event.key === "Enter") {
      event.preventDefault()
      this.add()
    }
  }

  add() {
    const val = this.inputTarget.value.trim()
    if (val && !this.tags.includes(val)) {
      this.tags.push(val)
      this.inputTarget.value = ""
      this.sync()
      this.render()
    }
  }

  remove(event) {
    const tag = event.currentTarget.dataset.tag
    this.tags = this.tags.filter(t => t !== tag)
    this.sync()
    this.render()
  }

  sync() {
    this.hiddenTarget.value = this.tags.join(",")
  }

  render() {
    this.tagsTarget.innerHTML = this.tags.map(tag => `
      <span class="inline-flex items-center gap-1 rounded-full bg-primary/10 px-3 py-1 text-xs font-medium text-primary">
        ${tag}
        <button type="button" data-action="click->tags-input#remove" data-tag="${tag}" class="hover:text-primary/70">
          <svg xmlns="http://www.w3.org/2000/svg" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M18 6 6 18"/><path d="m6 6 12 12"/></svg>
        </button>
      </span>
    `).join("")
  }
}
