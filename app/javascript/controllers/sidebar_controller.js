import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["desktop", "mobile", "overlay", "collapseIconExpanded", "collapseIconCollapsed"]

  connect() {
    const collapsed = localStorage.getItem("sidebar-collapsed") === "true"
    if (collapsed) this.applyCollapsed()
  }

  toggleCollapse() {
    const isCollapsed = this.desktopTarget.classList.contains("w-16")
    if (isCollapsed) {
      this.applyExpanded()
      localStorage.setItem("sidebar-collapsed", "false")
    } else {
      this.applyCollapsed()
      localStorage.setItem("sidebar-collapsed", "true")
    }
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

  applyCollapsed() {
    this.desktopTarget.classList.remove("w-64")
    this.desktopTarget.classList.add("w-16")
    this.desktopTarget.querySelectorAll(".sidebar-label").forEach(el => el.classList.add("hidden"))
    if (this.hasCollapseIconExpandedTarget) this.collapseIconExpandedTarget.classList.add("hidden")
    if (this.hasCollapseIconCollapsedTarget) this.collapseIconCollapsedTarget.classList.remove("hidden")
  }

  applyExpanded() {
    this.desktopTarget.classList.remove("w-16")
    this.desktopTarget.classList.add("w-64")
    this.desktopTarget.querySelectorAll(".sidebar-label").forEach(el => el.classList.remove("hidden"))
    if (this.hasCollapseIconExpandedTarget) this.collapseIconExpandedTarget.classList.remove("hidden")
    if (this.hasCollapseIconCollapsedTarget) this.collapseIconCollapsedTarget.classList.add("hidden")
  }
}
