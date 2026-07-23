class SearchDocument < ApplicationRecord
  belongs_to :project
  serialize :embedding, coder: JSON

  validates :source_type, :source_id, :title, :content, :url, :content_digest, :embedding, :source_created_at, presence: true
  validates :source_id, uniqueness: { scope: [ :project_id, :source_type ] }
end
