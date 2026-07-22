import test from "node:test"
import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"

const controller = await readFile(new URL("../../app/javascript/controllers/chat_scroll_controller.js", import.meta.url), "utf8")
const styles = await readFile(new URL("../../app/assets/tailwind/application.css", import.meta.url), "utf8")

test("chat starts at the latest message without an animated top-to-bottom jump", () => {
  assert.doesNotMatch(controller, /requestAnimationFrame\(\(\) => this\.scrollToBottom\(\)\)/)
  assert.match(controller, /connect\(\)\s*{[\s\S]*this\.scrollToBottom\(\)/)
  assert.doesNotMatch(styles, /\.message-scroll\s*{[^}]*scroll-smooth/)
})
