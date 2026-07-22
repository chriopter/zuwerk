class TodoComment < ApplicationRecord
  belongs_to :todo
  belongs_to :author, class_name: "User"
  has_rich_text :body

  validates :body, presence: true
end
