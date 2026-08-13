import { Controller } from "@hotwired/stimulus"

// Collects files for the chat composer from the picker, drag and drop, or a
// paste, and shows what will be sent. A file input's FileList is read-only, so
// the selection is rebuilt through a DataTransfer whenever it changes.
export default class extends Controller {
  static targets = ["input", "list", "submit"]
  static values = { max: { type: Number, default: 5 } }

  connect() {
    this.files = []
    this.depth = 0
    this.render()
  }

  open() { this.inputTarget.click() }

  picked() {
    this.add(this.inputTarget.files)
  }

  paste(event) {
    const files = Array.from(event.clipboardData?.files || [])
    if (files.length === 0) return

    event.preventDefault()
    this.add(files)
  }

  // dragenter/dragleave fire per element, so the highlight is reference counted;
  // dragover only has to keep the drop from being cancelled.
  dragenter(event) {
    if (!this.hasFiles(event)) return

    event.preventDefault()
    this.depth += 1
    this.element.classList.add("is-dropping")
  }

  dragover(event) {
    if (this.hasFiles(event)) event.preventDefault()
  }

  dragleave() {
    this.depth = Math.max(this.depth - 1, 0)
    if (this.depth === 0) this.element.classList.remove("is-dropping")
  }

  drop(event) {
    if (!this.hasFiles(event)) return

    event.preventDefault()
    this.depth = 0
    this.element.classList.remove("is-dropping")
    this.add(event.dataTransfer.files)
  }

  remove(event) {
    this.files.splice(Number(event.params.index), 1)
    this.sync()
  }

  hasFiles(event) {
    return Array.from(event.dataTransfer?.types || []).includes("Files")
  }

  add(files) {
    for (const file of files) {
      if (this.files.length >= this.maxValue) break
      if (this.files.some((existing) => this.same(existing, file))) continue
      this.files.push(file)
    }
    this.sync()
  }

  same(a, b) {
    return a.name === b.name && a.size === b.size && a.lastModified === b.lastModified
  }

  sync() {
    const transfer = new DataTransfer()
    this.files.forEach((file) => transfer.items.add(file))
    this.inputTarget.files = transfer.files
    this.render()
  }

  render() {
    this.releasePreviews()
    this.listTarget.replaceChildren(...this.files.map((file, index) => this.chip(file, index)))
    this.listTarget.hidden = this.files.length === 0
    this.refreshSubmit()
  }

  chip(file, index) {
    const chip = document.createElement("span")
    chip.className = "composer-chip"

    if (file.type.startsWith("image/")) {
      const url = URL.createObjectURL(file)
      this.previews.push(url)
      const thumbnail = document.createElement("img")
      thumbnail.className = "composer-chip-thumb"
      thumbnail.src = url
      thumbnail.alt = ""
      chip.append(thumbnail)
    }

    const name = document.createElement("span")
    name.className = "composer-chip-name"
    name.textContent = file.name
    chip.append(name)

    const remove = document.createElement("button")
    remove.type = "button"
    remove.className = "composer-chip-remove"
    remove.textContent = "×"
    remove.setAttribute("aria-label", `Remove ${file.name}`)
    remove.dataset.action = "attachments#remove"
    remove.dataset.attachmentsIndexParam = index
    chip.append(remove)

    return chip
  }

  releasePreviews() {
    ;(this.previews || []).forEach((url) => URL.revokeObjectURL(url))
    this.previews = []
  }

  // A message needs a body or at least one attachment, matching the server.
  refreshSubmit() {
    if (!this.hasSubmitTarget) return

    const body = this.element.querySelector(".composer-input")
    this.submitTarget.disabled = this.files.length === 0 && body?.value.trim() === ""
  }

  disconnect() { this.releasePreviews() }
}
