require "test_helper"

class ProjectLiveChatTest < ActionDispatch::IntegrationTest
  TURBO = { "Accept" => "text/vnd.turbo-stream.html, text/html, application/xhtml+xml" }.freeze

  setup do
    @human = User.create!(name: "Ada", email: "ada-live@example.com", password: "password1")
    @agent = User.create!(name: "Hermes", kind: :agent, api_token: "live-agent-token")
    @project = Project.create!(name: "Live project")
    @chat = @project.chat
    post session_path, params: { email: @human.email, password: "password1" }
  end

  test "the project home subscribes to the streams that feed it" do
    get project_path(@project)
    assert_response :success

    names = css_select("turbo-cable-stream-source").map { |source| source["signed-stream-name"] }
    assert_includes names, Turbo::StreamsChannel.signed_stream_name(@chat.home_stream)
    assert_includes names, Turbo::StreamsChannel.signed_stream_name(@project.agent_turn_stream)
  end

  test "the project home renders its messages under ids a broadcast can address" do
    mine = @chat.messages.create!(author: @human, body: "Mine")
    theirs = @chat.messages.create!(author: @agent, body: "Theirs")

    get project_path(@project)
    assert_select "#project_live_messages" do
      assert_select "##{mine.live_dom_id}.project-live-message.is-own[data-author-id='#{@human.id}']"
      assert_select "##{theirs.live_dom_id}.project-live-message.is-agent[data-author-id='#{@agent.id}']"
      assert_select "##{theirs.live_dom_id} time[datetime='#{theirs.created_at.iso8601}'][data-controller='relative-time']"
    end
    assert_select "form#project_chat_entry"
  end

  test "the empty prompt stays in the feed so an arriving message can push it aside" do
    get project_path(@project)
    assert_select "#project_live_messages .project-live-empty", count: 1
    assert_select "#project_live_messages .project-live-message", count: 0
  end

  # This is the exact render path a broadcast takes, so it catches helpers that
  # are missing outside a request.
  test "the feed partial renders standalone the way a broadcast renders it" do
    tail = ("complete " * 80).strip
    message = @chat.messages.create!(author: @agent, body: "**Bold** and #{tail}")
    html = ApplicationController.render(partial: "projects/live_message", locals: { chat_message: message, current_user: nil })

    assert_includes html, message.live_dom_id
    assert_includes html, "Bold and"
    assert_includes html, tail
    assert_not_includes html, "<strong>Bold</strong>", "the condensed feed shows plain text, not markup"
    assert_not_includes html, "is-own", "a broadcast is rendered for every viewer at once"
  end

  test "an attachment-only message still says something in the condensed feed" do
    upload = Rack::Test::UploadedFile.new(file_fixture("logo.png"), "image/png")
    message = @chat.messages.create!(author: @human, body: "", attachments: [ upload ])

    html = ApplicationController.render(partial: "projects/live_message", locals: { chat_message: message, current_user: nil })
    assert_includes html, "1 attachment"
  end

  test "sending from the project home swaps the composer instead of the page" do
    assert_difference -> { @chat.messages.count }, 1 do
      post project_chat_messages_path(@project), params: { return_to: "project", chat_message: { body: "Live send" } }, headers: TURBO
    end

    assert_response :success
    assert_match "target=\"project_chat_entry\"", response.body
    assert_match "action=\"replace\"", response.body
    assert_match "composer autofocus", response.body
    # The message arrives over the stream; appending it here would duplicate it.
    assert_no_match(/action="append"/, response.body)
    assert_no_match(/Live send/, response.body)
  end

  test "sending from the chat page swaps only the composer" do
    post project_chat_messages_path(@project), params: { chat_message: { body: "From chat" } }, headers: TURBO

    assert_response :success
    assert_match "target=\"chat_composer\"", response.body
    assert_no_match(/target="project_chat_entry"/, response.body)
  end

  test "a rejected message comes back with its errors and without a reload" do
    assert_no_difference -> { @chat.messages.count } do
      post project_chat_messages_path(@project), params: { return_to: "project", chat_message: { body: "  " } }, headers: TURBO
    end

    assert_response :unprocessable_entity
    assert_match "target=\"project_chat_entry\"", response.body
    assert_match "class=\"errors\"", response.body
  end

  test "without turbo the project composer falls back to a redirect" do
    post project_chat_messages_path(@project), params: { return_to: "project", chat_message: { body: "" } }

    assert_redirected_to project_path(@project)
    assert_not_nil flash[:alert]
  end
end
