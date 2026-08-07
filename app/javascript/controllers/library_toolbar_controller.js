import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["toggle"]

  toggle() {
    const open = this.element.classList.toggle("is-toolbar-open")
    this.toggleTarget.setAttribute("aria-expanded", open.toString())
  }
}
