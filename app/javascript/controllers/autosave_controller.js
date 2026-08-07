import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["status"]

  disconnect() {
    clearTimeout(this.timeout)
    this.request?.abort()
  }

  queue(event) {
    clearTimeout(this.timeout)
    this.reloadAfterSave ||= event.target.name?.endsWith("[parent_id]")
    this.#setStatus("Saving…")
    this.timeout = setTimeout(() => this.#persist(), 700)
  }

  submit(event) {
    event.preventDefault()
    clearTimeout(this.timeout)
    this.#persist()
  }

  async #persist() {
    this.request?.abort()
    this.request = new AbortController()
    const token = document.querySelector("meta[name='csrf-token']")?.content
    let response
    try {
      response = await fetch(this.element.action, {
        method: "POST",
        headers: { "Accept": "application/json", "X-CSRF-Token": token },
        body: new FormData(this.element),
        signal: this.request.signal
      })
    } catch (error) {
      if (error.name === "AbortError") return
      this.#setStatus("Could not save")
      return
    }

    if (response.ok) {
      this.#setStatus("Saved")
      if (this.reloadAfterSave) Turbo.visit(window.location.href, { action: "replace" })
    } else {
      this.#setStatus("Could not save")
    }
  }

  #setStatus(message) {
    if (this.hasStatusTarget) this.statusTarget.textContent = message
  }
}
