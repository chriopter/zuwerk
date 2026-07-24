import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "menu", "highlights"]
  static values = { users: Array }

  connect() {
    this.index = 0
    this.matches = []
    this.highlight()
  }

  update() {
    this.highlight()
    const token = this.#token()
    if (!token) return this.#close()

    const query = token.text.slice(1).toLowerCase()
    this.matches = this.usersValue.filter((user) =>
      user.handle.toLowerCase().startsWith(query) || user.name.toLowerCase().startsWith(query)
    ).slice(0, 6)
    if (this.matches.length === 0) return this.#close()

    this.index = Math.min(this.index, this.matches.length - 1)
    this.#render()
    this.menuTarget.hidden = false
  }

  keydown(event) {
    if (this.menuTarget.hidden) return

    switch (event.key) {
      case "ArrowDown":
        event.preventDefault()
        this.index = (this.index + 1) % this.matches.length
        this.#render()
        break
      case "ArrowUp":
        event.preventDefault()
        this.index = (this.index - 1 + this.matches.length) % this.matches.length
        this.#render()
        break
      case "Enter":
      case "Tab":
        event.preventDefault()
        event.stopImmediatePropagation()
        this.#insert(this.matches[this.index])
        break
      case "Escape":
        event.stopImmediatePropagation()
        this.#close()
        break
    }
  }

  pick(event) {
    const handle = event.currentTarget.dataset.handle
    this.#insert(this.matches.find((user) => user.handle === handle))
  }

  #insert(user) {
    if (!user) return
    const token = this.#token()
    if (!token) return

    const input = this.inputTarget
    const before = input.value.slice(0, token.start)
    const after = input.value.slice(input.selectionStart)
    input.value = `${before}@${user.handle} ${after}`
    const caret = token.start + user.handle.length + 2
    input.setSelectionRange(caret, caret)
    input.focus()
    input.dispatchEvent(new Event("input", { bubbles: true }))
    this.#close()
  }

  highlight() {
    if (!this.hasHighlightsTarget) return

    const handles = new Set(this.usersValue.map((user) => user.handle.toLowerCase()))
    const escape = (text) => text.replace(/[&<>]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;" }[c]))
    const html = escape(this.inputTarget.value).replace(/(^|\s)(@[\w-]+)/g, (match, prefix, token) =>
      handles.has(token.slice(1).toLowerCase()) ? `${prefix}<mark class="mention-token">${token}</mark>` : match
    )
    this.highlightsTarget.innerHTML = `${html}\n`
    this.highlightsTarget.scrollTop = this.inputTarget.scrollTop
  }

  #token() {
    const input = this.inputTarget
    const caret = input.selectionStart
    if (caret === null || caret !== input.selectionEnd) return null

    const before = input.value.slice(0, caret)
    const match = before.match(/(?:^|\s)(@[\w-]*)$/)
    if (!match) return null

    return { text: match[1], start: caret - match[1].length }
  }

  #close() {
    this.matches = []
    this.index = 0
    if (this.hasMenuTarget) this.menuTarget.hidden = true
  }

  #render() {
    this.menuTarget.innerHTML = this.matches.map((user, position) => `
      <button type="button" class="mention-option ${position === this.index ? "is-active" : ""}"
        data-handle="${user.handle}" data-action="mousedown->mention#pick:prevent">
        <span class="mention-option-avatar">${user.name.charAt(0).toUpperCase()}</span>
        <span class="mention-option-name">${user.name}</span>
        <span class="mention-option-handle">@${user.handle}</span>
      </button>`).join("")
  }
}
