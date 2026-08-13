import test from "node:test"
import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"

const source = await readFile(new URL("../../app/javascript/controllers/composer_dock_controller.js", import.meta.url), "utf8")
const styles = await readFile(new URL("../../app/assets/tailwind/application.css", import.meta.url), "utf8")
const layout = await readFile(new URL("../../app/views/layouts/application.html.erb", import.meta.url), "utf8")

// Load the controller without Stimulus by swapping its base class for a stub.
const module = await import(
  `data:text/javascript,${encodeURIComponent(source.replace(/^import .*stimulus.*$/m, "class Controller {}"))}`
)

function build({ dockHeight = 140, panelHeight = 600, viewportHeight = 800, offsetTop = 0 } = {}) {
  const properties = {}
  const listeners = []

  globalThis.window = { innerHeight: 800 }
  globalThis.window.visualViewport = {
    height: viewportHeight,
    offsetTop,
    addEventListener: (name) => listeners.push(name),
    removeEventListener: (name) => listeners.splice(listeners.indexOf(name), 1)
  }
  globalThis.ResizeObserver = class {
    constructor(callback) { this.callback = callback }
    observe() { this.observed = true }
    disconnect() { this.observed = false }
  }

  const controller = new module.default()
  controller.element = { clientHeight: panelHeight, style: { setProperty: (name, value) => { properties[name] = value } } }
  controller.dockTarget = { offsetHeight: dockHeight }
  return { controller, properties, listeners }
}

test("publishes the dock height so the feed can reserve room for it", () => {
  const { controller, properties } = build({ dockHeight: 152 })
  controller.connect()
  assert.equal(properties["--composer-space"], "152px")
  assert.equal(properties["--keyboard-inset"], "0px")
})

test("lifts the dock above the on-screen keyboard", () => {
  const { controller, properties } = build({ viewportHeight: 460 })
  controller.connect()
  assert.equal(properties["--keyboard-inset"], "300px")
})

test("accounts for a layout viewport the browser scrolled under the keyboard", () => {
  const { controller, properties } = build({ viewportHeight: 460, offsetTop: 100 })
  controller.connect()
  assert.equal(properties["--keyboard-inset"], "240px")
})

test("ignores the small viewport difference desktop pinch-zoom produces", () => {
  const { controller, properties } = build({ viewportHeight: 760 })
  controller.connect()
  assert.equal(properties["--keyboard-inset"], "0px")
})

test("never lifts the dock past the middle of the panel", () => {
  const { controller, properties } = build({ viewportHeight: 200, panelHeight: 400 })
  controller.connect()
  assert.equal(properties["--keyboard-inset"], "200px")
})

test("stops observing the viewport when the panel goes away", () => {
  const { controller, listeners } = build()
  controller.connect()
  assert.deepEqual(listeners, ["resize", "scroll"])
  controller.disconnect()
  assert.deepEqual(listeners, [])
  assert.equal(controller.observer.observed, false)
})

test("the dock is pinned to the panel rather than carried by the message flow", () => {
  assert.match(styles, /\.composer-dock\s*{\s*@apply[^;]*\babsolute\b[^;]*\bbottom-0\b/)
  assert.match(styles, /\.message-feed\s*{[\s\S]*?padding-bottom: calc\(var\(--composer-space\)/)
  assert.match(styles, /\.new-message-button\s*{[\s\S]*?bottom: calc\(var\(--composer-space\)/)
})

test("the chat page never scrolls the document out from under the dock", () => {
  assert.match(layout, /<html[^>]*h-svh overflow-hidden overscroll-none/)
  assert.match(styles, /\.workspace-top-shell\.is-chat-shell\s*{\s*@apply[^;]*\bh-svh\b/)
})

test("the project page entry sticks to the viewport while the document scrolls", () => {
  assert.match(styles, /\.project-chat-entry\s*{\s*@apply[^;]*\bsticky\b/)
  assert.match(styles, /\.project-chat-entry\s*{[\s\S]*?bottom: calc\(\.75rem/)
})
