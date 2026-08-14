import { Controller } from "@hotwired/stimulus"

// A Turbo Stream update is not a page load, so the browser will not honour the
// autofocus attribute on a composer that was swapped in after sending. Only the
// swapped-in copy mounts this, never the one the page was rendered with.
export default class extends Controller {
  connect() {
    this.element.focus()
    const end = this.element.value?.length ?? 0
    this.element.setSelectionRange?.(end, end)
  }
}
