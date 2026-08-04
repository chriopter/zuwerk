import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  dragStart(event) {
    this.dragged = event.currentTarget
    event.dataTransfer.effectAllowed = "move"
    event.dataTransfer.setData("text/plain", this.dragged.dataset.projectId)
    this.dragged.classList.add("project-directory-item-dragging")
  }

  dragOver(event) {
    event.preventDefault()
    event.dataTransfer.dropEffect = "move"
    this.#clearDropTarget()
    if (event.currentTarget !== this.dragged) event.currentTarget.classList.add("project-directory-item-drop-target")
  }

  async drop(event) {
    event.preventDefault()
    this.#clearDropTarget()
    const target = event.currentTarget
    if (!this.dragged || target === this.dragged) return

    const response = await fetch(`/projects/${this.dragged.dataset.projectId}/reorder`, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        "Accept": "application/json",
        "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content
      },
      body: JSON.stringify({ position: Number(target.dataset.position) })
    })

    if (response.ok) Turbo.visit(window.location.href, { action: "replace" })
    else window.location.reload()
  }

  dragEnd() {
    this.dragged?.classList.remove("project-directory-item-dragging")
    this.#clearDropTarget()
    this.dragged = null
  }

  #clearDropTarget() {
    this.element.querySelector(".project-directory-item-drop-target")?.classList.remove("project-directory-item-drop-target")
  }
}
