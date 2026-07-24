import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["label"]

  toggle() {
    const collapsed = this.element.classList.toggle("is-collapsed")
    this.labelTarget.textContent = collapsed ? "Show more" : "Show less"
  }
}
