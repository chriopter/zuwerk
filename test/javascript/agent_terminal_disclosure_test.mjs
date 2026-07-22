import assert from "node:assert/strict"
import fs from "node:fs"
import test from "node:test"

const source = fs.readFileSync(new URL("../../app/javascript/application.js", import.meta.url), "utf8")

test("optional agent terminal follows disclosure lifecycle", () => {
  assert.match(source, /cockpit\.dataset\.terminalEnabled !== "true"/)
  assert.match(source, /disclosure\.addEventListener\("toggle", syncTerminal\)/)
  assert.match(source, /disclosure\.open \? mountAgentTerminal\(cockpit\)/)
  assert.match(source, /cleanupMountedTerminal\(\)/)
  assert.match(source, /disclosure\.removeEventListener\("toggle", syncTerminal\)/)
})

test("agent terminal respects reduced motion", () => {
  assert.match(source, /cursorBlink: !window\.matchMedia\("\(prefers-reduced-motion: reduce\)"\)\.matches/)
})
