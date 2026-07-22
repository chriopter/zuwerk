// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"

import "lexxy"
import "@rails/activestorage"
import { createConsumer } from "@rails/actioncable"
import { Terminal } from "@xterm/xterm"
import { FitAddon } from "@xterm/addon-fit"

let cleanupAgentTerminal = () => {}

const mountAgentTerminal = () => {
  cleanupAgentTerminal()

  const cockpit = document.querySelector("[data-terminal-agent-id]")
  if (!cockpit || cockpit.dataset.terminalMounted === "true") return

  cockpit.dataset.terminalMounted = "true"
  const screen = cockpit.querySelector("[data-terminal-screen]")
  const terminal = new Terminal({
    cursorBlink: true,
    convertEol: false,
    fontFamily: "ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace",
    fontSize: 14,
    scrollback: 5_000,
    theme: { background: "#111318", foreground: "#e7e9ee", cursor: "#8fb4ff" }
  })
  const fit = new FitAddon()
  terminal.loadAddon(fit)
  terminal.open(screen)
  fit.fit()
  terminal.focus()

  let disposed = false
  let subscription
  let resizeTimer
  let connectedSize = ""
  const consumer = createConsumer()

  const connectTerminal = () => {
    if (disposed) return

    fit.fit()
    const rows = terminal.rows
    const columns = terminal.cols
    connectedSize = `${columns}x${rows}`
    subscription?.unsubscribe()
    terminal.reset()

    subscription = consumer.subscriptions.create(
      {
        channel: "AgentTerminalChannel",
        agent_id: cockpit.dataset.terminalAgentId,
        rows,
        columns
      },
      {
        connected() {
          cockpit.dataset.terminalConnected = "true"
        },
        disconnected() {
          cockpit.dataset.terminalConnected = "false"
        },
        rejected() {
          terminal.write("\r\nTerminal connection rejected.\r\n")
        },
        received(message) {
          if (message.type === "output") terminal.write(message.data)
          if (message.type === "error") terminal.write(`\r\n${message.message}\r\n`)
        }
      }
    )
  }

  const scheduleResize = () => {
    if (disposed) return
    clearTimeout(resizeTimer)
    resizeTimer = setTimeout(() => {
      fit.fit()
      const fittedSize = `${terminal.cols}x${terminal.rows}`
      if (fittedSize !== connectedSize) connectTerminal()
    }, 200)
  }

  const inputDisposable = terminal.onData((data) => subscription?.send({ type: "input", data }))
  const reconnectButton = cockpit.querySelector("[data-terminal-reconnect]")
  const reconnect = () => {
    consumer.connect()
    connectTerminal()
    terminal.focus()
  }
  const resizeObserver = new ResizeObserver(scheduleResize)

  reconnectButton?.addEventListener("click", reconnect)
  resizeObserver.observe(screen)
  connectTerminal()

  cleanupAgentTerminal = () => {
    if (disposed) return
    disposed = true
    clearTimeout(resizeTimer)
    inputDisposable.dispose()
    reconnectButton?.removeEventListener("click", reconnect)
    resizeObserver.disconnect()
    subscription?.unsubscribe()
    consumer.disconnect()
    cockpit.removeAttribute("data-terminal-mounted")
    terminal.dispose()
    cleanupAgentTerminal = () => {}
  }
}

document.addEventListener("turbo:load", mountAgentTerminal)
document.addEventListener("turbo:before-cache", () => cleanupAgentTerminal())
document.addEventListener("turbo:before-render", () => cleanupAgentTerminal())
