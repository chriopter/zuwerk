import test from "node:test"
import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"

const controller = await readFile(new URL("../../app/javascript/controllers/todo_sort_controller.js", import.meta.url), "utf8")

test("todo drag and drop persists hierarchy and position through the project route", () => {
  assert.match(controller, /method:\s*"PATCH"/)
  assert.match(controller, /parent_id:\s*parentId,\s*position/)
  assert.match(controller, /\/projects\/\$\{this\.projectIdValue\}\/todos\/\$\{this\.dragged\.dataset\.todoId\}\/reorder/)
  assert.match(controller, /X-CSRF-Token/)
  assert.match(controller, /Turbo\.visit/)
  assert.match(controller, /nest \? this\.#childCount\(target\)/)
})
