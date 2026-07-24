class TaskList < ApplicationRecord
  belongs_to :project
  has_many :tasks, dependent: :restrict_with_error

  validates :name, presence: true, length: { maximum: 80 }, uniqueness: { scope: :project_id }
end
