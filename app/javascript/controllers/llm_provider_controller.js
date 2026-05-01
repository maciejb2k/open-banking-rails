import { Controller } from "@hotwired/stimulus"

// Cascades the model <select> options when the provider <select> changes.
//
// Server renders the full provider→models map as a JSON value so the
// dropdown updates without a roundtrip. The default model for the picked
// provider becomes the new selection (overriding whatever was there) since
// a model from one vendor never belongs to another.
//
// Values
//   models   (object) – { providerKey: ["model-a", "model-b"], ... }
//   defaults (object) – { providerKey: "default-model", ... }
//
// Targets
//   provider – the provider <select>
//   model    – the model <select>
export default class extends Controller {
  static values  = { models: Object, defaults: Object }
  static targets = ["provider", "model"]

  change() {
    const provider = this.providerTarget.value
    const models   = this.modelsValue[provider] || []
    const fallback = this.defaultsValue[provider] || models[0] || ""

    this.modelTarget.innerHTML = ""
    for (const m of models) {
      const opt = document.createElement("option")
      opt.value = m
      opt.textContent = m
      this.modelTarget.appendChild(opt)
    }
    this.modelTarget.value = fallback
  }
}
