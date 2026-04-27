import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "results", "item", "group"]

  connect() {
    this.boundKeydown = this.onGlobalKeydown.bind(this)
    document.addEventListener("keydown", this.boundKeydown)
    this.activeIndex = -1
  }

  disconnect() {
    document.removeEventListener("keydown", this.boundKeydown)
  }

  open() {
    this.element.classList.remove("hidden")
    document.body.classList.add("overflow-hidden")
    setTimeout(() => this.inputTarget.focus(), 50)
    this.inputTarget.value = ""
    this.showAll()
  }

  close() {
    this.element.classList.add("hidden")
    document.body.classList.remove("overflow-hidden")
    this.activeIndex = -1
  }

  filter() {
    const query = this.inputTarget.value.toLowerCase()
    this.itemTargets.forEach(item => {
      const match = item.textContent.toLowerCase().includes(query)
      item.classList.toggle("hidden", !match)
    })
    this.groupTargets.forEach(group => {
      const hasVisible = Array.from(group.querySelectorAll("[data-command-palette-target='item']"))
        .some(item => !item.classList.contains("hidden"))
      group.classList.toggle("hidden", !hasVisible)
    })
  }

  navigate(event) {
    if (event.key === "Escape") { this.close(); return }
    const visible = this.itemTargets.filter(i => !i.classList.contains("hidden"))
    if (event.key === "ArrowDown") {
      event.preventDefault()
      this.activeIndex = Math.min(this.activeIndex + 1, visible.length - 1)
    } else if (event.key === "ArrowUp") {
      event.preventDefault()
      this.activeIndex = Math.max(this.activeIndex - 1, 0)
    } else if (event.key === "Enter" && visible[this.activeIndex]) {
      event.preventDefault()
      visible[this.activeIndex].click()
      this.close()
      return
    }
    visible.forEach((item, i) => {
      item.classList.toggle("bg-primary/10", i === this.activeIndex)
      item.classList.toggle("text-primary", i === this.activeIndex)
    })
  }

  onGlobalKeydown(event) {
    if ((event.metaKey || event.ctrlKey) && event.key === "k") {
      event.preventDefault()
      this.element.classList.contains("hidden") ? this.open() : this.close()
    }
  }

  showAll() {
    this.itemTargets.forEach(item => item.classList.remove("hidden"))
    this.groupTargets.forEach(group => group.classList.remove("hidden"))
  }
}
