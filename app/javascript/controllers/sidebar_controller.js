import { Controller } from "@hotwired/stimulus"

// Collapsed state lives on <html> as `.sidebar-collapsed`. The class is
// applied before first paint by an inline script in the layout <head>, and
// the visual rules are a `sidebar-collapsed:` Tailwind variant - so a
// refresh paints in the correct state instead of animating from
// expanded → collapsed.
export default class extends Controller {
  static targets = ["mobile", "overlay"]

  toggleCollapse() {
    const root = document.documentElement
    const collapsed = !root.classList.contains("sidebar-collapsed")
    root.classList.toggle("sidebar-collapsed", collapsed)
    localStorage.setItem("sidebar-collapsed", String(collapsed))
  }

  openMobile() {
    this.mobileTarget.classList.remove("-translate-x-full")
    this.mobileTarget.classList.add("translate-x-0")
    this.overlayTarget.classList.remove("hidden")
  }

  closeMobile() {
    this.mobileTarget.classList.remove("translate-x-0")
    this.mobileTarget.classList.add("-translate-x-full")
    this.overlayTarget.classList.add("hidden")
  }
}
