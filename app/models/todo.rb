class Todo < ApplicationRecord
  belongs_to :project
  belongs_to :creator, class_name: "User"
  has_many :comments, class_name: "TodoComment", dependent: :destroy
  has_rich_text :description

  enum :status, { open: 0, completed: 1 }

  validates :title, presence: true, length: { maximum: 160 }
end
