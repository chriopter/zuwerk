import test from "node:test"
import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"

const controller = await readFile(new URL("../../app/javascript/controllers/page_tree_controller.js", import.meta.url), "utf8")

test("page tree drag and drop persists nesting and sibling order", () => {
  assert.match(controller, /method:\s*"PATCH"/)
  assert.match(controller, /parent_id:\s*parentId,\s*position/)
  assert.match(controller, /dataset\.reorderUrl/)
  assert.match(controller, /mode === "inside" \? target\.dataset\.pageId/)
  assert.match(controller, /ratio < 0\.25/)
  assert.match(controller, /ratio > 0\.75/)
  assert.match(controller, /X-CSRF-Token/)
  assert.match(controller, /Turbo\.visit/)
})
