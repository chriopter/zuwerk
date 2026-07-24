import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { projectId: Number }

  dragStart(event) {
    this.dragged = event.currentTarget
    event.dataTransfer.effectAllowed = "move"
    event.dataTransfer.setData("text/plain", this.dragged.dataset.taskId)
    this.dragged.classList.add("opacity-40")
  }

  dragOver(event) {
    event.preventDefault()
    event.dataTransfer.dropEffect = "move"
  }

  async drop(event) {
    event.preventDefault()
    event.stopPropagation()
    const target = event.currentTarget
    if (!this.dragged || target === this.dragged) return

    const nest = event.target.closest(".task-nest-target")
    const parentId = nest ? target.dataset.taskId : target.dataset.parentId
    const position = nest ? this.#childCount(target) : Number(target.dataset.position)
    await this.#persist(parentId, position)
  }

  dragOverRoot(event) {
    if (event.target === event.currentTarget) event.preventDefault()
  }

  async dropRoot(event) {
    if (event.target !== event.currentTarget || !this.dragged) return
    event.preventDefault()
    await this.#persist(null, event.currentTarget.children.length)
  }

  dragEnd() {
    this.dragged?.classList.remove("opacity-40")
    this.dragged = null
  }

  #childCount(item) {
    return Array.from(item.children).find((child) => child.matches("ol"))?.children.length || 0
  }

  async #persist(parentId, position) {
    const token = document.querySelector("meta[name='csrf-token']")?.content
    const response = await fetch(`/projects/${this.projectIdValue}/tasks/${this.dragged.dataset.taskId}/reorder`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json", "Accept": "application/json", "X-CSRF-Token": token },
      body: JSON.stringify({ parent_id: parentId, position })
    })

    if (response.ok) Turbo.visit(window.location.href, { action: "replace" })
    else window.location.reload()
  }
}
