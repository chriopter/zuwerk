class LibraryPageFile < ApplicationRecord
  belongs_to :library_page
  belongs_to :creator, class_name: "User", optional: true
  has_one_attached :file

  validates :name, presence: true, length: { maximum: 255 }
end
