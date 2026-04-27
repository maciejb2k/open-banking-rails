import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  clearAll() {
    this.element.querySelectorAll("input[type=text], input[type=search]").forEach(el => { el.value = "" })
    this.element.querySelectorAll("select").forEach(el => { el.selectedIndex = 0 })
    this.element.querySelectorAll("input[type=checkbox]").forEach(el => { el.checked = false })
  }
}
