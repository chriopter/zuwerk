import test from "node:test"
import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"

const controller = await readFile(new URL("../../app/javascript/controllers/autosave_controller.js", import.meta.url), "utf8")

test("page autosave debounces form updates and reports persistence", () => {
  assert.match(controller, /setTimeout\(\(\) => this\.#persist\(\), 700\)/)
  assert.match(controller, /new FormData\(this\.element\)/)
  assert.match(controller, /"Accept": "application\/json"/)
  assert.match(controller, /endsWith\("\[parent_id\]"\)/)
  assert.match(controller, /this\.request\?\.abort\(\)/)
  assert.match(controller, /this\.#setStatus\("Saved"\)/)
  assert.match(controller, /Turbo\.visit/)
})
