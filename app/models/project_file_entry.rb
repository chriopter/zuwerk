class ProjectFileEntry < ApplicationRecord
  KINDS = %w[folder file].freeze
  MAX_FILE_SIZE = 10.megabytes
  MAX_DEPTH = 20

  belongs_to :project
  belongs_to :creator, class_name: "User"
  belongs_to :parent, class_name: "ProjectFileEntry", optional: true
  has_many :children, class_name: "ProjectFileEntry", foreign_key: :parent_id, dependent: :destroy, inverse_of: :parent
  has_one_attached :file

  enum :kind, KINDS.index_by(&:itself), validate: true

  before_validation :normalize_name

  validates :name, presence: true
  validates :name_key, presence: true, uniqueness: { scope: [ :project_id, :parent_id ], case_sensitive: false }
  validate :safe_name
  validate :parent_is_folder_in_project
  validate :depth_is_bounded
  validate :attachment_matches_kind

  def lineage
    nodes = []
    node = self
    while node
      nodes.unshift(node)
      node = node.parent
    end
    nodes
  end

  private
    def normalize_name
      self.name = name.to_s.unicode_normalize(:nfkc).strip
      self.name_key = name.downcase
    end

    def safe_name
      invalid = name.in?([ ".", ".." ]) || name.match?(/[\x00-\x1f\x7f\\\/]/) || name.bytesize > 255
      errors.add(:name, "must be one safe path component of at most 255 bytes") if invalid
    end

    def parent_is_folder_in_project
      return unless parent
      errors.add(:parent, "must be a folder in this project") unless parent.folder? && parent.project_id == project_id
    end

    def depth_is_bounded
      depth = 0
      seen = Set.new
      node = parent
      while node
        if node == self || (node.id && seen.include?(node.id))
          errors.add(:parent, "cannot create a folder cycle")
          break
        end
        seen << node.id if node.id
        depth += 1
        if depth >= MAX_DEPTH
          errors.add(:parent, "cannot exceed #{MAX_DEPTH} folder levels")
          break
        end
        node = node.parent
      end
    end

    def attachment_matches_kind
      if folder? && file.attached?
        errors.add(:file, "cannot be attached to a folder")
      elsif file? && !file.attached?
        errors.add(:file, "must be attached")
      elsif file? && file.blob.byte_size.zero?
        errors.add(:file, "cannot be empty")
      elsif file? && file.blob.byte_size > MAX_FILE_SIZE
        errors.add(:file, "must be 10 MB or smaller")
      end
    end
end
