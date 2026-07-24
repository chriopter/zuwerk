import test from "node:test"
import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"

const controller = await readFile(new URL("../../app/javascript/controllers/kanban_controller.js", import.meta.url), "utf8")

test("kanban drag and drop persists the task workflow status", () => {
  assert.match(controller, /method:\s*"PATCH"/)
  assert.match(controller, /task:\s*\{\s*status:\s*column\.dataset\.status\s*\}/)
  assert.match(controller, /\/projects\/\$\{this\.projectIdValue\}\/tasks\/\$\{this\.dragged\.dataset\.taskId\}/)
  assert.match(controller, /X-CSRF-Token/)
  assert.match(controller, /Turbo\.visit/)
})
