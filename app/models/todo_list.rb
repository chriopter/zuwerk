class TodoList < ApplicationRecord
  belongs_to :project
  has_many :todos, dependent: :nullify

  validates :name, presence: true, length: { maximum: 80 }
end
