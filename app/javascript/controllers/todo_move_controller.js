import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { projectId: Number }

  listDragStart(event) {
    event.stopPropagation()
    this.draggedList = event.currentTarget.closest(".todo-list-card")
    event.dataTransfer.effectAllowed = "move"
    event.dataTransfer.setData("text/plain", this.draggedList.dataset.listId)
    this.draggedList.classList.add("todo-list-row-dragging")
  }

  dragStart(event) {
    this.dragged = event.currentTarget
    event.dataTransfer.effectAllowed = "move"
    event.dataTransfer.setData("text/plain", this.dragged.dataset.todoId)
    this.dragged.classList.add("todo-list-row-dragging")
  }

  dragOver(event) {
    if (!this.dragged && !this.draggedList) return
    event.preventDefault()
    event.dataTransfer.dropEffect = "move"
    event.currentTarget.classList.add("is-drop-target")
  }

  dragLeave(event) {
    event.currentTarget.classList.remove("is-drop-target")
  }

  async drop(event) {
    event.preventDefault()
    const target = event.currentTarget
    target.classList.remove("is-drop-target")
    if (this.draggedList) {
      if (this.draggedList === target || !target.dataset.listId) return
      await this.#patch(`/projects/${this.projectIdValue}/lists/${this.draggedList.dataset.listId}/reorder`,
        { position: Number(target.dataset.listPosition) })
      return
    }

    if (!this.dragged) return
    if (this.dragged.closest(".todo-list-card") === target) return
    await this.#patch(`/projects/${this.projectIdValue}/todos/${this.dragged.dataset.todoId}/reorder`,
      { todo_list_id: target.dataset.listId })
  }

  async #patch(url, body) {
    const response = await fetch(url, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        "Accept": "application/json",
        "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content
      },
      body: JSON.stringify(body)
    })

    if (response.ok) Turbo.visit(window.location.href, { action: "replace" })
    else window.location.reload()
  }

  dragEnd() {
    this.dragged?.classList.remove("todo-list-row-dragging")
    this.draggedList?.classList.remove("todo-list-row-dragging")
    this.dragged = null
    this.draggedList = null
  }
}
