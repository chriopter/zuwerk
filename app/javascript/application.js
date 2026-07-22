// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"

import "lexxy"
import "@rails/activestorage"
import { Terminal } from "@xterm/xterm"
import { FitAddon } from "@xterm/addon-fit"

const mountAgentTerminal = () => {
  const cockpit = document.querySelector("[data-terminal-agent-id]")
  if (!cockpit || cockpit.dataset.terminalMounted === "true") return

  cockpit.dataset.terminalMounted = "true"
  const screen = cockpit.querySelector("[data-terminal-screen]")
  const terminal = new Terminal({
    cursorBlink: true,
    convertEol: true,
    fontFamily: "ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace",
    fontSize: 14,
    scrollback: 2_000,
    theme: { background: "#111318", foreground: "#e7e9ee", cursor: "#8fb4ff" }
  })
  const fit = new FitAddon()
  terminal.loadAddon(fit)
  terminal.open(screen)
  fit.fit()

  const url = cockpit.dataset.terminalUrl
  const csrf = document.querySelector("meta[name='csrf-token']")?.content
  let fetching = false
  let writeQueue = Promise.resolve()

  const refresh = async () => {
    if (fetching || cockpit.dataset.terminalEnabled !== "true") return
    fetching = true
    try {
      const response = await fetch(url, { headers: { Accept: "application/json" } })
      const data = await response.json()
      if (!response.ok) throw new Error(data.error || "Terminal unavailable")
      terminal.write(`\u001b[2J\u001b[H${data.output}`)
    } catch (error) {
      terminal.write(`\u001b[2J\u001b[H\r\n${error.message}\r\n`)
    } finally {
      fetching = false
    }
  }

  terminal.onData((input) => {
    if (cockpit.dataset.terminalEnabled !== "true") return

    writeQueue = writeQueue.then(async () => {
      const response = await fetch(url, {
        method: "PATCH",
        headers: { "Content-Type": "application/json", "X-CSRF-Token": csrf, Accept: "application/json" },
        body: JSON.stringify({ input })
      })
      if (!response.ok) {
        const data = await response.json()
        throw new Error(data.error || "Terminal input failed")
      }
      window.setTimeout(refresh, 80)
    }).catch((error) => {
      terminal.write(`\r\n${error.message}\r\n`)
    })
  })

  cockpit.querySelector("[data-terminal-reconnect]")?.addEventListener("click", refresh)
  window.addEventListener("resize", () => fit.fit())
  refresh()
  cockpit.terminalTimer = window.setInterval(refresh, 750)
}

document.addEventListener("turbo:load", mountAgentTerminal)
document.addEventListener("turbo:before-cache", () => {
  const cockpit = document.querySelector("[data-terminal-agent-id]")
  if (cockpit?.terminalTimer) window.clearInterval(cockpit.terminalTimer)
})
