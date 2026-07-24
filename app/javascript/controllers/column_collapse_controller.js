import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { key: String }

  connect() {
    if (localStorage.getItem(this.#storageKey) === "1") this.element.classList.add("is-collapsed")
  }

  toggle(event) {
    event.preventDefault()
    const collapsed = this.element.classList.toggle("is-collapsed")
    localStorage.setItem(this.#storageKey, collapsed ? "1" : "0")
  }

  get #storageKey() {
    return `kanban-column-${this.keyValue}`
  }
}
