class Message < ApplicationRecord
  belongs_to :author, class_name: "User"
  has_many :reactions, dependent: :destroy
  validates :body, presence: true, length: { maximum: 4_000 }
  after_create_commit -> { broadcast_append_to "messages", target: "messages", partial: "messages/message", locals: { current_user: nil } }
end
