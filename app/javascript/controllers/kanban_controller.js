import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["column", "cards", "card"]
  static values = { projectId: Number }

  dragStart(event) {
    this.dragged = event.currentTarget
    event.dataTransfer.effectAllowed = "move"
    event.dataTransfer.setData("text/plain", this.dragged.dataset.todoId)
    requestAnimationFrame(() => this.dragged.classList.add("kanban-card-dragging"))
  }

  dragEnd() {
    this.dragged?.classList.remove("kanban-card-dragging")
    this.columnTargets.forEach(column => column.classList.remove("kanban-column-over"))
    this.dragged = null
  }

  dragOver(event) {
    event.preventDefault()
    event.dataTransfer.dropEffect = "move"
    event.currentTarget.classList.add("kanban-column-over")
  }

  async drop(event) {
    event.preventDefault()
    const column = event.currentTarget
    column.classList.remove("kanban-column-over")
    if (!this.dragged) return
    const response = await fetch(`/projects/${this.projectIdValue}/todos/${this.dragged.dataset.todoId}`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json", "Accept": "text/html", "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content },
      body: JSON.stringify({ todo: { status: column.dataset.status } })
    })
    if (response.ok) Turbo.visit(window.location.href, { action: "replace" })
    else window.location.reload()
  }
}