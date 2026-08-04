import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  navigate(event) {
    if (event.defaultPrevented || event.repeat || event.metaKey || event.ctrlKey || event.altKey || this.#isEditing(event.target)) return
    if (!["1", "2", "3", "4"].includes(event.key)) return

    const link = this.element.querySelector(`[data-shortcut="${event.key}"]`)
    if (!link) return

    event.preventDefault()
    link.click()
  }

  #isEditing(target) {
    return target instanceof Element && Boolean(target.closest("input, textarea, select, [contenteditable], lexxy-editor"))
  }
}
