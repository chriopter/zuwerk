class Project < ApplicationRecord
  has_many :search_documents, dependent: :destroy
  has_one :chat, dependent: :destroy
  has_many :tasks, dependent: :destroy
  has_many :task_lists, dependent: :destroy
  has_many :briefings, dependent: :destroy
  has_many :briefing_comments, through: :briefings, source: :comments
  has_many :file_entries, class_name: "ProjectFileEntry", dependent: :destroy
  after_create :create_default_chat!
  after_create :create_default_task_list!

  validates :name, presence: true, length: { maximum: 80 }, uniqueness: { case_sensitive: false }

  def self.default
    find_or_create_by!(name: "Zuwerk")
  end

  def default_task_list
    task_lists.order(:position, :id).first || with_lock { task_lists.create!(name: "Tasks", position: 0) }
  end

  def agent_turn_stream
    "project_#{id}_agent_turns"
  end

  private

  def create_default_chat!
    create_chat!
  end

  def create_default_task_list!
    task_lists.create!(name: "Tasks", position: 0)
  end
end
