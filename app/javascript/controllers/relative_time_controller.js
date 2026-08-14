import { Controller } from "@hotwired/stimulus"

// Keeps "3 minutes ago" honest on a page that never reloads. The server still
// renders the text, so this only takes over once the page is live.
export default class extends Controller {
  static TICK = 30_000

  connect() {
    this.stamp = Date.parse(this.element.getAttribute("datetime"))
    this.refresh()
    if (!Number.isNaN(this.stamp)) this.timer = setInterval(() => this.refresh(), this.constructor.TICK)
  }

  disconnect() {
    clearInterval(this.timer)
  }

  refresh() {
    if (Number.isNaN(this.stamp)) return
    this.element.textContent = this.constructor.phrase(Date.now() - this.stamp)
  }

  // Matches Rails' time_ago_in_words closely enough that a live message and a
  // reloaded one read the same.
  static phrase(elapsed) {
    const minutes = Math.round(Math.max(elapsed, 0) / 60_000)
    if (minutes < 1) return "less than a minute ago"
    if (minutes === 1) return "1 minute ago"
    if (minutes < 45) return `${minutes} minutes ago`

    const hours = Math.round(minutes / 60)
    if (minutes < 90) return "about 1 hour ago"
    if (hours < 24) return `about ${hours} hours ago`

    const days = Math.round(hours / 24)
    if (days === 1) return "1 day ago"
    if (days < 30) return `${days} days ago`

    const months = Math.round(days / 30)
    if (months === 1) return "about 1 month ago"
    if (months < 12) return `${months} months ago`

    const years = Math.floor(months / 12)
    return years === 1 ? "about 1 year ago" : `about ${years} years ago`
  }
}
