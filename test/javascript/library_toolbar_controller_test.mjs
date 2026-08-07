import test from "node:test"
import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"

const controller = await readFile(new URL("../../app/javascript/controllers/library_toolbar_controller.js", import.meta.url), "utf8")

test("library formatting toolbar is expanded on demand", () => {
  assert.match(controller, /classList\.toggle\("is-toolbar-open"\)/)
  assert.match(controller, /setAttribute\("aria-expanded", open\.toString\(\)\)/)
})
