import { Controller } from "@hotwired/stimulus"

// Keeps the composer floating over the bottom of the chat panel. It publishes
// the dock height so the message feed can reserve room for it, and lifts the
// dock above the on-screen keyboard on touch devices.
export default class extends Controller {
  static targets = ["dock"]

  connect() {
    this.measure = this.measure.bind(this)
    this.observer = new ResizeObserver(this.measure)
    this.observer.observe(this.dockTarget)
    this.viewport = window.visualViewport
    this.viewport?.addEventListener("resize", this.measure)
    this.viewport?.addEventListener("scroll", this.measure)
    this.measure()
  }

  disconnect() {
    this.observer?.disconnect()
    this.viewport?.removeEventListener("resize", this.measure)
    this.viewport?.removeEventListener("scroll", this.measure)
  }

  measure() {
    this.element.style.setProperty("--composer-space", `${Math.round(this.dockTarget.offsetHeight)}px`)
    this.element.style.setProperty("--keyboard-inset", `${this.keyboardInset()}px`)
  }

  // How much of the layout viewport the on-screen keyboard covers. Desktop
  // pinch-zoom produces small differences too, so ignore anything tiny, and
  // never lift the dock past the middle of the panel.
  keyboardInset() {
    if (!this.viewport) return 0
    const covered = window.innerHeight - this.viewport.height - this.viewport.offsetTop
    if (covered < 80) return 0
    return Math.round(Math.min(covered, this.element.clientHeight / 2))
  }
}
