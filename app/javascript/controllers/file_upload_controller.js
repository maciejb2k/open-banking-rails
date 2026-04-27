import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "dropzone", "filename"]

  open() {
    this.inputTarget.click()
  }

  fileSelected() {
    const file = this.inputTarget.files[0]
    if (file && this.hasFilenameTarget) {
      this.filenameTarget.textContent = file.name
    }
  }

  dragOver(event) {
    event.preventDefault()
    this.dropzoneTarget.classList.add("border-primary", "bg-primary/5")
  }

  dragLeave() {
    this.dropzoneTarget.classList.remove("border-primary", "bg-primary/5")
  }

  drop(event) {
    event.preventDefault()
    this.dragLeave()
    const file = event.dataTransfer.files[0]
    if (file) {
      const dt = new DataTransfer()
      dt.items.add(file)
      this.inputTarget.files = dt.files
      if (this.hasFilenameTarget) this.filenameTarget.textContent = file.name
    }
  }
}
