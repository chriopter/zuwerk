import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["viewport", "button"]

  connect() {
    this.nearBottom = true
    this.scrollToBottom()
    this.observer = new MutationObserver(() => this.contentChanged())
    this.observer.observe(this.viewportTarget, { childList: true, subtree: true, characterData: true })
  }

  disconnect() { this.observer?.disconnect() }

  track() {
    this.nearBottom = this.distanceFromBottom() < 120
    if (this.nearBottom) this.buttonTarget.classList.add("hidden")
  }

  contentChanged() {
    if (this.nearBottom) this.scrollToBottom()
    else this.buttonTarget.classList.remove("hidden")
  }

  scrollToBottom() {
    this.viewportTarget.scrollTop = this.viewportTarget.scrollHeight
    this.nearBottom = true
    this.buttonTarget.classList.add("hidden")
  }

  distanceFromBottom() {
    return this.viewportTarget.scrollHeight - this.viewportTarget.scrollTop - this.viewportTarget.clientHeight
  }
}
