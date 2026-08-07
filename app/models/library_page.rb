class LibraryPage < ApplicationRecord
  MAX_DEPTH = 20

  has_ancestry orphan_strategy: :destroy

  belongs_to :project
  belongs_to :creator, class_name: "User", optional: true
  has_many :files, class_name: "LibraryPageFile", dependent: :destroy
  has_rich_text :content

  scope :ordered, -> { order(:position, :id) }

  before_validation :normalize_title

  validates :title, presence: true, length: { maximum: 160 }
  validate :title_is_unique_among_siblings
  validate :parent_belongs_to_project
  validate :depth_is_bounded

  def lineage
    path
  end

  def move_to!(parent:, position:)
    target_position = Integer(position)
    validate_move_target!(parent)

    project.with_lock do
      reload
      validate_move_target!(parent)
      old_parent = self.parent
      old_scope = sibling_scope(old_parent)
      new_scope = sibling_scope(parent)
      same_scope = old_parent == parent
      old_siblings = old_scope.where.not(id: id).ordered.to_a
      new_siblings = same_scope ? old_siblings.dup : new_scope.where.not(id: id).ordered.to_a
      target_position = target_position.clamp(0, new_siblings.length)

      self.parent = parent
      self.position = target_position
      save!

      old_siblings.each_with_index { |sibling, index| sibling.update_column(:position, index) } unless same_scope
      new_siblings.insert(target_position, self)
      new_siblings.each_with_index { |sibling, index| sibling.update_column(:position, index) unless sibling == self }
    end
  end

  private
    def normalize_title
      self.title = title.to_s.unicode_normalize(:nfkc).strip
    end

    def title_is_unique_among_siblings
      return if title.blank? || !project

      siblings = project.library_pages.where(ancestry: ancestry).where("LOWER(title) = ?", title.downcase)
      siblings = siblings.where.not(id: id) if persisted?
      errors.add(:title, "has already been used here") if siblings.exists?
    end

    def parent_belongs_to_project
      errors.add(:parent, "must belong to this project") if parent && parent.project_id != project_id
    end

    def depth_is_bounded
      errors.add(:parent, "cannot exceed #{MAX_DEPTH} levels") if depth >= MAX_DEPTH
    end

    def sibling_scope(parent)
      parent ? parent.children : project.library_pages.roots
    end

    def validate_move_target!(new_parent)
      if new_parent && new_parent.project_id != project_id
        errors.add(:parent, "must belong to this project")
      elsif new_parent == self || (new_parent && new_parent.descendant_of?(self))
        errors.add(:parent, "cannot be nested below itself")
      elsif new_parent && new_parent.depth >= MAX_DEPTH - 1
        errors.add(:parent, "cannot exceed #{MAX_DEPTH} levels")
      end
      raise ActiveRecord::RecordInvalid, self if errors.any?
    end
end
