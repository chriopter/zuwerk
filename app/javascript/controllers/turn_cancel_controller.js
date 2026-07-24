import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["cancelForm"]

  click(event) {
    const item = this.element.querySelector(".avatar-stack-item")
    if (!item?.classList.contains("is-working")) return

    event.preventDefault()
    if (item.classList.contains("is-confirming")) {
      this.cancelFormTarget.requestSubmit()
      return
    }

    item.classList.add("is-confirming")
    clearTimeout(this.timer)
    this.timer = setTimeout(() => item.classList.remove("is-confirming"), 3000)
  }

  disconnect() {
    clearTimeout(this.timer)
  }
}
