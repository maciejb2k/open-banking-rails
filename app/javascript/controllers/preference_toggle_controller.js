import { Controller } from "@hotwired/stimulus"

// Generic boolean preference toggle.
//
// Toggles a CSS class on a scope element (default: <html>) and persists
// the state in a cookie so the next page render reflects it without FOUC.
// Reuse for: privacy mode, dark mode, density, feature flags, etc.
//
// Values
//   name    (string)  – cookie name (e.g. "privacy_mode", "dark_mode")
//   class   (string)  – CSS class to toggle on the scope element
//   scope   (string)  – CSS selector for the scope element. Defaults to ":root" (= <html>).
//   maxAge  (number)  – cookie max-age in seconds. Defaults to 1 year.
//
// Targets
//   iconOn  – shown when ON  (hidden when OFF)
//   iconOff – shown when OFF (hidden when ON)
//   label   – textContent set from data-on-label / data-off-label, if present
//
// Example
//   <button data-controller="preference-toggle"
//           data-action="click->preference-toggle#toggle"
//           data-preference-toggle-name-value="privacy_mode"
//           data-preference-toggle-class-value="privacy-mode">
//     <span data-preference-toggle-target="iconOff">eye</span>
//     <span data-preference-toggle-target="iconOn" class="hidden">eye-off</span>
//   </button>

const ONE_YEAR = 60 * 60 * 24 * 365

export default class extends Controller {
  static values = {
    name:   String,
    class:  String,
    scope:  { type: String, default: ":root" },
    maxAge: { type: Number, default: ONE_YEAR }
  }
  static targets = ["iconOn", "iconOff", "label"]

  connect() {
    this.sync()
  }

  toggle(event) {
    event?.preventDefault()
    const next = !this.isOn()
    this.scopeElement.classList.toggle(this.classValue, next)
    this.writeCookie(next)
    this.sync(next)
  }

  isOn() {
    return this.scopeElement.classList.contains(this.classValue)
  }

  get scopeElement() {
    if (this.scopeValue === ":root") return document.documentElement
    return document.querySelector(this.scopeValue) || document.documentElement
  }

  writeCookie(on) {
    const base = `${this.nameValue}=; path=/; SameSite=Lax`
    document.cookie = on
      ? `${this.nameValue}=1; path=/; max-age=${this.maxAgeValue}; SameSite=Lax`
      : `${base} max-age=0`
  }

  sync(on = this.isOn()) {
    this.element.setAttribute("aria-pressed", on ? "true" : "false")
    if (this.hasIconOnTarget)  this.iconOnTarget.classList.toggle("hidden", !on)
    if (this.hasIconOffTarget) this.iconOffTarget.classList.toggle("hidden",  on)
    if (this.hasLabelTarget) {
      const onText  = this.labelTarget.dataset.onLabel
      const offText = this.labelTarget.dataset.offLabel
      if (onText && offText) this.labelTarget.textContent = on ? onText : offText
    }
  }
}
