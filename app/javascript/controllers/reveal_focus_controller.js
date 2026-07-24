import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  focus() {
    if (this.element.open) this.element.querySelector("input[type='text']")?.focus()
  }
}
