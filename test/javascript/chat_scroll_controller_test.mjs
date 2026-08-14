import test from "node:test"
import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"

const controller = await readFile(new URL("../../app/javascript/controllers/chat_scroll_controller.js", import.meta.url), "utf8")
const styles = await readFile(new URL("../../app/assets/tailwind/application.css", import.meta.url), "utf8")

// Load the controller without Stimulus by swapping its base class for a stub.
const module = await import(
  `data:text/javascript,${encodeURIComponent(controller.replace(/^import .*stimulus.*$/m, "class Controller {}"))}`
)

function build({ withButton = true, scrollHeight = 2000, clientHeight = 500, scrollTop = 0 } = {}) {
  globalThis.MutationObserver = class {
    constructor(callback) { this.callback = callback }
    observe() {}
    disconnect() {}
  }
  globalThis.ResizeObserver = class {
    constructor(callback) { this.callback = callback }
    observe() {}
    disconnect() {}
  }

  const classes = []
  const instance = new module.default()
  instance.viewportTarget = { scrollHeight, clientHeight, scrollTop, firstElementChild: null }
  instance.hasButtonTarget = withButton
  if (withButton) {
    instance.buttonTarget = { classList: { add: (name) => classes.push(`+${name}`), remove: (name) => classes.push(`-${name}`) } }
  }
  return { instance, classes }
}

test("chat starts at the latest message without an animated top-to-bottom jump", () => {
  assert.doesNotMatch(controller, /requestAnimationFrame\(\(\) => this\.scrollToBottom\(\)\)/)
  assert.match(controller, /connect\(\)\s*{[\s\S]*this\.scrollToBottom\(\)/)
  assert.doesNotMatch(styles, /\.message-scroll\s*{[^}]*scroll-smooth/)
})

test("scrolls a feed that has no catch-up button without throwing", () => {
  const { instance } = build({ withButton: false })
  instance.connect()
  assert.equal(instance.viewportTarget.scrollTop, 2000)

  instance.viewportTarget.scrollHeight = 2400
  instance.contentChanged()
  assert.equal(instance.viewportTarget.scrollTop, 2400)

  instance.viewportTarget.scrollTop = 0
  instance.track()
  assert.equal(instance.nearBottom, false)
  instance.contentChanged()
  assert.equal(instance.viewportTarget.scrollTop, 0, "a reader who scrolled up is not yanked back down")
})

test("still offers the catch-up button when the feed has one", () => {
  const { instance, classes } = build()
  instance.connect()
  assert.deepEqual(classes, [ "+hidden" ])

  instance.viewportTarget.scrollTop = 0
  instance.track()
  instance.contentChanged()
  assert.deepEqual(classes, [ "+hidden", "-hidden" ])
})
