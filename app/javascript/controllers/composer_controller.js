import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() { this.grow() }
  grow() {
    this.element.style.height = "auto"
    this.element.style.height = `${Math.min(this.element.scrollHeight, 180)}px`
  }
  keydown(event) {
    if (event.key === "Enter" && !event.shiftKey) {
      event.preventDefault()
      // requestSubmit() ignores a disabled submit button, so check it here:
      // the chat composer disables Send until there is a body or an attachment.
      if (this.submitButton?.disabled) return
      this.element.form.requestSubmit()
    }
  }

  get submitButton() {
    return this.element.form?.querySelector("input[type=submit], button[type=submit]")
  }
}
