import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  dragStart(event) {
    this.dragged = event.currentTarget
    event.dataTransfer.effectAllowed = "move"
    event.dataTransfer.setData("text/plain", this.dragged.dataset.pageId)
    this.dragged.classList.add("is-dragging")
  }

  dragOver(event) {
    event.preventDefault()
    event.stopPropagation()
    event.dataTransfer.dropEffect = "move"
    this.#markTarget(event.currentTarget, this.#dropMode(event))
  }

  async drop(event) {
    event.preventDefault()
    event.stopPropagation()
    const target = event.currentTarget
    if (!this.dragged || target === this.dragged) return

    const mode = this.#dropMode(event)
    const parentId = mode === "inside" ? target.dataset.pageId : (target.dataset.parentId || null)
    const position = mode === "before"
      ? Number(target.dataset.position)
      : mode === "after"
        ? Number(target.dataset.position) + 1
        : Number(target.dataset.childCount)
    await this.#persist(parentId, position)
  }

  dragOverRoot(event) {
    if (event.target === event.currentTarget) event.preventDefault()
  }

  async dropRoot(event) {
    if (event.target !== event.currentTarget || !this.dragged) return
    event.preventDefault()
    const rootCount = this.element.querySelectorAll(":scope > ul > .library-tree-branch").length
    await this.#persist(null, rootCount)
  }

  dragEnd() {
    this.dragged?.classList.remove("is-dragging")
    this.dragged = null
    this.#clearTargets()
  }

  #dropMode(event) {
    const rectangle = event.currentTarget.getBoundingClientRect()
    const ratio = (event.clientY - rectangle.top) / rectangle.height
    if (ratio < 0.25) return "before"
    if (ratio > 0.75) return "after"
    return "inside"
  }

  #markTarget(target, mode) {
    this.#clearTargets()
    target.classList.add(`is-drop-${mode}`)
  }

  #clearTargets() {
    this.element.querySelectorAll(".is-drop-before, .is-drop-inside, .is-drop-after").forEach((row) => {
      row.classList.remove("is-drop-before", "is-drop-inside", "is-drop-after")
    })
  }

  async #persist(parentId, position) {
    const token = document.querySelector("meta[name='csrf-token']")?.content
    const response = await fetch(this.dragged.dataset.reorderUrl, {
      method: "PATCH",
      headers: { "Content-Type": "application/json", "Accept": "application/json", "X-CSRF-Token": token },
      body: JSON.stringify({ parent_id: parentId, position })
    })

    if (response.ok) Turbo.visit(window.location.href, { action: "replace" })
    else window.location.reload()
  }
}
