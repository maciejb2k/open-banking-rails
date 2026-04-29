import { Controller } from "@hotwired/stimulus"

// Toggles visibility of the rule-pattern fields inside the classification
// modal based on which propagation mode (radio) is selected. The
// "create_rule" mode reveals a row of select+text inputs; the other two
// modes hide them.
export default class extends Controller {
  static targets = ["ruleFields", "createRule"]

  connect() {
    this.update()
  }

  switch() {
    this.update()
  }

  update() {
    if (!this.hasRuleFieldsTarget) return
    const showRuleFields = this.hasCreateRuleTarget && this.createRuleTarget.checked
    this.ruleFieldsTarget.classList.toggle("hidden", !showRuleFields)
    this.ruleFieldsTarget.classList.toggle("grid", showRuleFields)
  }
}
