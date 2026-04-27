import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["tab", "panel"]
  static values = { current: String }

  switch(event) {
    const id = event.currentTarget.dataset.tabId
    this.currentValue = id
  }

  currentValueChanged() {
    this.tabTargets.forEach(tab => {
      const active = tab.dataset.tabId === this.currentValue
      tab.classList.toggle("border-primary", active)
      tab.classList.toggle("text-primary", active)
      tab.classList.toggle("border-transparent", !active)
      tab.classList.toggle("text-muted-foreground", !active)
    })
    this.panelTargets.forEach(panel => {
      panel.classList.toggle("hidden", panel.dataset.panelId !== this.currentValue)
    })
  }
}
