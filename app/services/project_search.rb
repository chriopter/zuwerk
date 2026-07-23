class ProjectSearch
  Result = Data.define(:type, :source_id, :project_id, :title, :content, :url, :score, :created_at)
  Unavailable = Class.new(StandardError)
  MODEL = "sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2"
  MODEL_REVISION = "e8f8c211226b894fcb81acc59f3b34ba3efd5f42"
  MODEL_FILE = "model_quint8_avx2"
  MAX_SOURCE_CHARACTERS = 12_000
  MAX_ATTACHMENT_BYTES = 200.kilobytes

  class LocalEmbedder
    def call(texts)
      self.class.mutex.synchronize { self.class.model.call(Array(texts)) }
    rescue StandardError => error
      Rails.logger.error("Semantic search embedding failed: #{error.class}: #{error.message}")
      raise Unavailable, "Semantic search is temporarily unavailable."
    end

    class << self
      def model
        require "informers"
        @model ||= Informers.pipeline(
          "embedding",
          MODEL,
          cache_dir: Rails.root.join("storage/models").to_s,
          model_file_name: MODEL_FILE,
          revision: MODEL_REVISION,
          session_options: { intra_op_num_threads: 1, inter_op_num_threads: 1 }
        )
      end

      def mutex
        @mutex ||= Mutex.new
      end
    end
  end

  class << self
    attr_writer :embedder_factory

    def embedder_factory
      @embedder_factory ||= -> { LocalEmbedder.new }
    end
  end

  def initialize(project, embedder: nil)
    @project = project
    @embedder = embedder || self.class.embedder_factory.call
  end

  def call(query, limit: 10, types: nil)
    query = query.to_s.strip
    return [] if query.blank?

    reconcile_index!
    scope = SearchDocument.where(project_id: @project.id)
    allowed_types = Array(types).map(&:to_s).presence
    scope = scope.where(source_type: allowed_types) if allowed_types
    documents = scope.order(:id).to_a
    return [] if documents.empty?

    query_embedding = @embedder.call([ query ]).first
    query_terms = terms(query)

    scored_documents = documents.map do |document|
      semantic_score = dot(query_embedding, document.embedding)
      lexical_score = lexical_score(query_terms, document.title, document.content)
      Result.new(
        type: document.source_type,
        source_id: document.source_id,
        project_id: document.project_id,
        title: document.title,
        content: document.content,
        url: document.url,
        score: (semantic_score * 0.8) + (lexical_score * 0.2),
        created_at: document.source_created_at
      )
    end

    scored_documents.sort_by { |document| [ -document.score, -document.created_at.to_f, document.type, document.source_id ] }.first(limit)
  end

  private
    def reconcile_index!
      sources = source_documents
      existing = SearchDocument.where(project_id: @project.id).index_by { |document| [ document.source_type, document.source_id ] }
      source_keys = sources.map { |source| [ source.type, source.source_id ] }
      stale_ids = existing.except(*source_keys).values.map(&:id)
      SearchDocument.where(id: stale_ids).delete_all if stale_ids.any?

      changed = sources.filter_map do |source|
        digest = Digest::SHA256.hexdigest([ MODEL, MODEL_REVISION, MODEL_FILE, source.title, source.content, source.url ].join("\0"))
        indexed = existing[[ source.type, source.source_id ]]
        [ source, digest ] unless indexed&.content_digest == digest
      end

      changed.each_slice(4) do |batch|
        embeddings = @embedder.call(batch.map { |source, _digest| source.content })
        rows = batch.zip(embeddings).map do |(source, digest), embedding|
          {
            project_id: @project.id,
            source_type: source.type,
            source_id: source.source_id,
            title: source.title,
            content: source.content,
            url: source.url,
            content_digest: digest,
            embedding: embedding,
            source_created_at: source.created_at,
            created_at: Time.current,
            updated_at: Time.current
          }
        end
        SearchDocument.upsert_all(rows, unique_by: [ :project_id, :source_type, :source_id ])
      end
    end

    def source_documents
      [ *message_documents, *todo_documents, *comment_documents, *attachment_documents, *board_post_documents ]
    end

    def message_documents
      @project.messages.includes(:author).order(:id).map do |message|
        result("message", message.id, "Chat · #{message.author.name}", message.body, chat_project_path(@project, anchor: "message_#{message.id}"), message.created_at)
      end
    end

    def todo_documents
      @project.todos.includes(:rich_text_description).order(:id).map do |todo|
        content = [ todo.title, todo.description.to_plain_text ].reject(&:blank?).join("\n")
        result("todo", todo.id, "Task ##{todo.id} · #{todo.title}", content, project_todo_path(@project, todo), todo.created_at)
      end
    end

    def comment_documents
      TodoComment.joins(:todo).where(todos: { project_id: @project.id }).includes(:author, :rich_text_body, :todo).order(:id).map do |comment|
        result("todo_comment", comment.id, "Task ##{comment.todo_id} · Kommentar von #{comment.author.name}", comment.body.to_plain_text, project_todo_path(@project, comment.todo, anchor: "todo_comment_#{comment.id}"), comment.created_at)
      end
    end

    def attachment_documents
      @project.messages.includes(attachments_attachments: :blob).order(:id).flat_map do |message|
        message.attachments.filter_map do |attachment|
          next unless attachment.blob.byte_size <= MAX_ATTACHMENT_BYTES
          next unless attachment.content_type.to_s.start_with?("text/")

          content = attachment.download.force_encoding(Encoding::UTF_8).scrub
          result("attachment", attachment.id, "Datei · #{attachment.filename}", content, chat_project_path(@project, anchor: "message_#{message.id}"), message.created_at)
        end
      end
    end

    def board_post_documents
      @project.board_posts.published.includes(:author, :rich_text_body).order(:id).map do |post|
        result("board_post", post.id, "Board · #{post.title}", post.body.to_plain_text, project_board_post_path(@project, post), post.published_at)
      end
    end

    def result(type, source_id, title, content, url, created_at)
      Result.new(type:, source_id:, project_id: @project.id, title:, content: content.to_s.first(MAX_SOURCE_CHARACTERS), url:, score: 0.0, created_at:)
    end

    def dot(left, right)
      left.zip(right).sum { |a, b| a.to_f * b.to_f }
    end

    def terms(text)
      text.downcase.scan(/[[:alnum:]]{2,}/).uniq
    end

    def lexical_score(query_terms, title, content)
      return 0.0 if query_terms.empty?

      source_terms = terms("#{title} #{content}")
      (query_terms & source_terms).length.fdiv(query_terms.length)
    end

    def chat_project_path(...)
      Rails.application.routes.url_helpers.chat_project_path(...)
    end

    def project_todo_path(...)
      Rails.application.routes.url_helpers.project_todo_path(...)
    end

    def project_board_post_path(...)
      Rails.application.routes.url_helpers.project_board_post_path(...)
    end
end
