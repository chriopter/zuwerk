import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.sync()
    this.observer = new MutationObserver(() => this.sync())
    this.observer.observe(this.element, { childList: true, subtree: true })
  }

  disconnect() {
    this.observer?.disconnect()
  }

  sync() {
    const source = this.element.querySelector("#agent_presence")
    if (!source) return
    const ids = JSON.parse(source.dataset.workingAgentIds || "[]")
    this.element.querySelectorAll(".avatar-stack [data-agent-id]").forEach((item) =>
      item.classList.toggle("is-working", ids.includes(Number(item.dataset.agentId)))
    )
  }
}
