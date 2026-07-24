import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["display", "editor", "input"]

  connect() {
    this.original = this.hasInputTarget ? this.inputTarget.value : null
  }

  reveal() {
    if (this.hasDisplayTarget) this.displayTarget.hidden = true
    if (this.hasEditorTarget) {
      this.editorTarget.hidden = false
      this.editorTarget.querySelector("input, textarea, [contenteditable], lexxy-editor")?.focus()
    }
  }

  submitIfChanged() {
    if (!this.hasInputTarget) return
    if (this.inputTarget.value !== this.original && this.inputTarget.value.trim() !== "") {
      this.inputTarget.form.requestSubmit()
    }
  }

  keydown(event) {
    if (event.key === "Escape") {
      this.inputTarget.value = this.original
      this.inputTarget.blur()
    }
  }
}
