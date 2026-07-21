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
      this.element.form.requestSubmit()
    }
  }
}
