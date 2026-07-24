import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["select", "output", "description"]
  static values = { prompts: Object, descriptions: Object }

  connect() {
    this.update()
  }

  update() {
    const type = this.selectTarget.value
    this.outputTarget.textContent = this.promptsValue[type] || ""
    this.descriptionTarget.textContent = this.descriptionsValue[type] || ""
  }
}
