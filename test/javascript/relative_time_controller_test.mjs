import test from "node:test"
import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"

const source = await readFile(new URL("../../app/javascript/controllers/relative_time_controller.js", import.meta.url), "utf8")

// Load the controller without Stimulus by swapping its base class for a stub.
const module = await import(
  `data:text/javascript,${encodeURIComponent(source.replace(/^import .*stimulus.*$/m, "class Controller {}"))}`
)
const RelativeTime = module.default

function build(datetime) {
  const element = {
    textContent: "",
    getAttribute: (name) => (name === "datetime" ? datetime : null)
  }
  const controller = new RelativeTime()
  controller.element = element
  return { controller, element }
}

test("reads the same as Rails' time_ago_in_words", () => {
  assert.equal(RelativeTime.phrase(20 * 1000), "less than a minute ago")
  assert.equal(RelativeTime.phrase(60 * 1000), "1 minute ago")
  assert.equal(RelativeTime.phrase(9 * 60 * 1000), "9 minutes ago")
  assert.equal(RelativeTime.phrase(44 * 60 * 1000), "44 minutes ago")
  assert.equal(RelativeTime.phrase(60 * 60 * 1000), "about 1 hour ago")
  assert.equal(RelativeTime.phrase(5 * 60 * 60 * 1000), "about 5 hours ago")
  assert.equal(RelativeTime.phrase(26 * 60 * 60 * 1000), "1 day ago")
  assert.equal(RelativeTime.phrase(4 * 24 * 60 * 60 * 1000), "4 days ago")
  assert.equal(RelativeTime.phrase(40 * 24 * 60 * 60 * 1000), "about 1 month ago")
  assert.equal(RelativeTime.phrase(400 * 24 * 60 * 60 * 1000), "about 1 year ago")
})

test("a clock running backwards never produces a negative age", () => {
  assert.equal(RelativeTime.phrase(-90 * 1000), "less than a minute ago")
})

test("rewrites the stamp on connect and keeps rewriting it", (t) => {
  t.mock.timers.enable({ apis: ["Date", "setInterval"], now: new Date("2026-08-14T12:00:00Z") })
  const { controller, element } = build("2026-08-14T11:55:00Z")

  controller.connect()
  assert.equal(element.textContent, "5 minutes ago")

  t.mock.timers.tick(20 * 60 * 1000)
  assert.equal(element.textContent, "25 minutes ago")

  controller.disconnect()
  t.mock.timers.tick(60 * 60 * 1000)
  assert.equal(element.textContent, "25 minutes ago")
})

test("leaves the server-rendered text alone when the stamp is unreadable", (t) => {
  t.mock.timers.enable({ apis: ["Date", "setInterval"] })
  const { controller, element } = build("not a date")
  element.textContent = "2 minutes ago"

  controller.connect()
  t.mock.timers.tick(10 * 60 * 1000)

  assert.equal(element.textContent, "2 minutes ago")
  controller.disconnect()
})
