import test from "node:test"
import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"

const read = (path) => readFile(new URL(`../../${path}`, import.meta.url), "utf8")

const projectPage = await read("app/views/projects/show.html.erb")
const liveMessage = await read("app/views/projects/_live_message.html.erb")
const chatPage = await read("app/views/chats/show.html.erb")
const createStream = await read("app/views/chat_messages/create.turbo_stream.erb")
const chatMessage = await read("app/models/chat_message.rb")
const chat = await read("app/models/chat.rb")
const reactions = await read("app/views/reactions/_reactions.html.erb")
const styles = await read("app/assets/tailwind/application.css")

test("the project home subscribes to everything it renders", () => {
  assert.match(projectPage, /turbo_stream_from @chat\.home_stream/)
  assert.match(projectPage, /turbo_stream_from @project\.agent_turn_stream/)
  assert.match(projectPage, /turbo_stream_from Current\.account\.agent_presence_stream/)
  assert.match(projectPage, /id="project_live_messages"/)
  assert.match(projectPage, /data-controller="chat-scroll"/)
  assert.match(projectPage, /data-chat-scroll-target="viewport"/)
})

test("the chat message reaches both feeds in their own markup", () => {
  assert.match(chat, /def home_stream/)
  assert.match(chatMessage, /broadcast_append_to chat\.home_stream, target: "project_live_messages", partial: "projects\/live_message"/)
  assert.match(chatMessage, /broadcast_replace_to chat\.home_stream, target: live_dom_id/)
  assert.match(chatMessage, /Turbo::StreamsChannel\.broadcast_remove_to chat\.home_stream, target: live_dom_id/)
  // The two surfaces must not fight over one dom id.
  assert.match(chatMessage, /def live_dom_id = ActionView::RecordIdentifier\.dom_id\(self, :live\)/)
  assert.match(liveMessage, /id="<%= chat_message\.live_dom_id %>"/)
})

test("a broadcast renders for nobody, so the viewer is resolved in the browser", () => {
  assert.match(liveMessage, /data-author-id="<%= chat_message\.author_id %>"/)
  assert.match(projectPage, /data-controller="own-messages"/)
  assert.match(reactions, /data: \{ author_id: reaction\.author_id \}/)
})

test("sending replaces only the composer instead of reloading the page", () => {
  assert.match(createStream, /turbo_stream\.replace "project_chat_entry", partial: "projects\/chat_entry"/)
  assert.match(createStream, /turbo_stream\.replace "chat_composer", partial: "chats\/composer"/)
  assert.match(chatPage, /render "chats\/composer"/)
  // Nothing may append the message here — the stream already delivers it.
  assert.doesNotMatch(createStream, /turbo_stream\.append/)
})

test("only the swapped-in composer grabs focus", async () => {
  const projectEntry = await read("app/views/projects/_chat_entry.html.erb")
  const chatComposer = await read("app/views/chats/_composer.html.erb")

  for (const partial of [ projectEntry, chatComposer ]) {
    assert.match(partial, /local_assigns\[:focus\] \? "composer autofocus" : "composer"/)
    assert.match(partial, /data: \{ controller: composer,/)
    assert.doesNotMatch(partial, /autofocus: true/, "a page load must not steal focus")
  }
  assert.equal(createStream.match(/focus: true/g).length, 2)
  assert.doesNotMatch(projectPage, /focus: true/)
  assert.doesNotMatch(chatPage, /focus: true/)
})

test("a live feed does not leave a stale prompt or a stale timestamp behind", () => {
  assert.match(styles, /\.project-live-messages:has\(\.project-live-message\) \.project-live-empty \{ @apply hidden; \}/)
  // A justify-end scroll container makes its own overflow unreachable, and the
  // feed no longer stops at the eight messages the page was rendered with.
  assert.doesNotMatch(styles, /\.project-live-messages \{[^}]*justify-end/)
  assert.match(styles, /\.project-live-messages > article:first-of-type \{ @apply mt-auto; \}/)
  assert.match(liveMessage, /data-controller="relative-time"/)
  assert.match(liveMessage, /datetime="<%= chat_message\.created_at\.iso8601 %>"/)
})
