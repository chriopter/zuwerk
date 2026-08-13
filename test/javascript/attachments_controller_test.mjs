import test from "node:test"
import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"

const path = new URL("../../app/javascript/controllers/attachments_controller.js", import.meta.url)
const source = await readFile(path, "utf8")
const composer = await readFile(new URL("../../app/javascript/controllers/composer_controller.js", import.meta.url), "utf8")

// Load the controller without Stimulus by swapping its base class for a stub.
const module = await import(
  `data:text/javascript,${encodeURIComponent(source.replace(/^import .*stimulus.*$/m, "class Controller {}"))}`
)

class DataTransfer {
  constructor() {
    this.files = []
    this.items = { add: (file) => this.files.push(file) }
  }
}

function element() {
  return {
    className: "", textContent: "", hidden: false, dataset: {}, children: [],
    append: function (...nodes) { this.children.push(...nodes) },
    replaceChildren: function (...nodes) { this.children = nodes },
    setAttribute() {},
    classList: { add() {}, remove() {} },
    querySelector: () => null
  }
}

function build({ max = 5 } = {}) {
  globalThis.DataTransfer = DataTransfer
  globalThis.document = { createElement: () => element() }
  globalThis.URL = { createObjectURL: () => "blob:preview", revokeObjectURL: () => revoked++ }

  const controller = new module.default()
  controller.inputTarget = { files: [] }
  controller.listTarget = element()
  controller.element = element()
  controller.hasSubmitTarget = false
  controller.maxValue = max
  controller.connect()
  return controller
}

let revoked = 0
const file = (name, type = "text/plain", size = 10) => ({ name, type, size, lastModified: 1 })

test("keeps the file input in sync with the collected files", () => {
  const controller = build()
  controller.add([ file("a.txt"), file("b.png", "image/png") ])

  assert.deepEqual(controller.inputTarget.files.map((f) => f.name), [ "a.txt", "b.png" ])
  assert.equal(controller.listTarget.hidden, false)
  assert.equal(controller.listTarget.children.length, 2)
})

test("ignores duplicates and stops at the maximum", () => {
  const controller = build({ max: 2 })
  controller.add([ file("a.txt"), file("a.txt") ])
  assert.equal(controller.files.length, 1)

  controller.add([ file("b.txt"), file("c.txt") ])
  assert.deepEqual(controller.files.map((f) => f.name), [ "a.txt", "b.txt" ])
})

test("removing a file rebuilds the input and hides an empty list", () => {
  const controller = build()
  controller.add([ file("a.txt"), file("b.txt") ])
  controller.remove({ params: { index: 0 } })
  assert.deepEqual(controller.inputTarget.files.map((f) => f.name), [ "b.txt" ])

  controller.remove({ params: { index: 0 } })
  assert.equal(controller.inputTarget.files.length, 0)
  assert.equal(controller.listTarget.hidden, true)
})

test("releases image preview URLs instead of leaking them", () => {
  const controller = build()
  revoked = 0
  controller.add([ file("shot.png", "image/png") ])
  controller.remove({ params: { index: 0 } })
  controller.disconnect()

  assert.ok(revoked >= 1)
})

test("a drop or paste of files is accepted and a plain text drag is left alone", () => {
  const controller = build()
  const dropped = []
  const event = (types, files) => ({
    dataTransfer: { types, files },
    clipboardData: { files },
    preventDefault: () => dropped.push(true)
  })

  controller.drop(event([ "Files" ], [ file("a.txt") ]))
  assert.equal(controller.files.length, 1)

  controller.drop(event([ "text/plain" ], [ file("b.txt") ]))
  assert.equal(controller.files.length, 1, "a text drag must not be captured")

  controller.paste(event([], [ file("pasted.png", "image/png") ]))
  assert.equal(controller.files.length, 2)
})

test("only dragenter counts toward the drop highlight so a hover cannot strand it", () => {
  // dragover fires continuously while hovering, so counting it would never unwind.
  assert.match(source, /dragenter\(event\)\s*{[\s\S]*this\.depth \+= 1/)
  assert.doesNotMatch(source, /dragover\(event\)\s*{[\s\S]*this\.depth \+= 1/)
})

test("Enter does not submit a composer with nothing to send", () => {
  assert.match(composer, /this\.submitButton\?\.disabled/)
})
