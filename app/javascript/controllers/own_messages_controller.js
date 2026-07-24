import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { user: Number }

  connect() {
    this.tag()
    this.observer = new MutationObserver(() => this.tag())
    this.observer.observe(this.element, { childList: true })
  }

  disconnect() {
    this.observer?.disconnect()
  }

  tag() {
    this.element.querySelectorAll(`[data-author-id="${this.userValue}"]`).forEach((row) => row.classList.add("is-own"))
  }
}
