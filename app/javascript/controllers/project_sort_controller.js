import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  dragStart(event) {
    this.dragged = event.currentTarget
    event.dataTransfer.effectAllowed = "move"
    event.dataTransfer.setData("text/plain", this.dragged.dataset.projectId)
    this.dragged.classList.add("project-directory-card-dragging")
  }

  dragOver(event) {
    event.preventDefault()
    event.dataTransfer.dropEffect = "move"
  }

  async drop(event) {
    event.preventDefault()
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
    this.dragged?.classList.remove("project-directory-card-dragging")
    this.dragged = null
  }
}
