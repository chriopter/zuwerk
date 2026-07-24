require "test_helper"

class ProjectSearchTest < ActiveSupport::TestCase
  class SemanticFixtureEmbedder
    attr_reader :batches

    def initialize
      @batches = []
    end

    def call(texts)
      @batches << Array(texts)
      Array(texts).map do |text|
        normalized = text.downcase
        if normalized.match?(/verbindungsproblem|netzwerkverbindung|connection failure/)
          [ 1.0, 0.0, 0.0 ]
        elsif normalized.match?(/kuchen|cake/)
          [ 0.0, 1.0, 0.0 ]
        else
          [ 0.0, 0.0, 1.0 ]
        end
      end
    end
  end

  test "finds semantically related project chat and task sources without lexical overlap" do
    human = User.create!(name: "Search Human", email: "search-human@example.com", password: "password1")
    project = Project.create!(name: "Searchable")
    other_project = Project.create!(name: "Private")
    matching_message = project.chat.messages.create!(author: human, body: "Die Netzwerkverbindung wurde durch einen Neustart repariert.")
    project.chat.messages.create!(author: human, body: "Zum Mittag gibt es Kuchen.")
    matching_task = project.tasks.create!(creator: human, title: "Bridge stabilisieren", description: "Connection failure dauerhaft verhindern")
    matching_task.comments.create!(author: human, body: "Der Socket braucht einen Heartbeat.")
    agent = User.create!(name: "Search Reporter", kind: :agent)
    briefing = project.briefings.create!(creator: human, agent: agent, title: "Briefing report", frequency: "weekly", prompt: "Report")
    briefing_comment = briefing.run_now!
    briefing_comment.publish!("Die Dokumentation beschreibt den stabilen Betrieb.", event: briefing_comment.agent_event)
    file_entry = project.file_entries.new(kind: "file", name: "network-notes.txt", creator: human)
    file_entry.file.attach(io: StringIO.new("Network connection recovery notes"), filename: "network-notes.txt", content_type: "text/plain")
    file_entry.save!
    other_project.chat.messages.create!(author: human, body: "Verbindungsproblem in einem anderen Projekt")

    embedder = SemanticFixtureEmbedder.new
    results = ProjectSearch.new(project, embedder: embedder).call("Verbindungsproblem", limit: 3)

    assert_equal 6, SearchDocument.where(project: project).count
    assert_equal [ "chat_message", "task" ], results.first(2).map(&:type).sort
    assert_equal matching_message.id, results.find { |result| result.type == "chat_message" }.source_id
    assert_equal matching_task.id, results.find { |result| result.type == "task" }.source_id
    assert_equal project.id, results.first.project_id
    assert_equal "/projects/#{project.id}/chat#chat_message_#{matching_message.id}", results.find { |result| result.type == "chat_message" }.url
    briefing_document = SearchDocument.find_by!(project: project, source_type: "briefing_comment", source_id: briefing_comment.id)
    assert_equal "/projects/#{project.id}/briefings/#{briefing.id}#briefing_comment_#{briefing_comment.id}", briefing_document.url
    assert_includes briefing_document.content, "stabilen Betrieb"
    file_document = SearchDocument.find_by!(project: project, source_type: "project_file", source_id: file_entry.id)
    assert_equal "/projects/#{project.id}/files#file_entry_#{file_entry.id}", file_document.url
    assert_includes file_document.content, "Network connection"
    assert results.none? { |result| result.content.include?("anderen Projekt") }

    embedder.batches.clear
    ProjectSearch.new(project, embedder: embedder).call("Kuchen", limit: 2)
    assert_equal [ [ "Kuchen" ] ], embedder.batches

    comment_id = matching_task.comments.first.id
    matching_message.update!(body: "Die Datenbankmigration ist jetzt das relevante Thema.")
    matching_task.destroy!
    ProjectSearch.new(project, embedder: embedder).call("Migration", limit: 2)
    assert_equal "Die Datenbankmigration ist jetzt das relevante Thema.", SearchDocument.find_by!(source_type: "chat_message", source_id: matching_message.id).content
    assert_not SearchDocument.exists?(source_type: "task", source_id: matching_task.id)
    assert_not SearchDocument.exists?(source_type: "task_comment", source_id: comment_id)
  end
end
