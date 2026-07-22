class Todo < ApplicationRecord
  has_ancestry orphan_strategy: :restrict

  belongs_to :project
  belongs_to :creator, class_name: "User"
  has_many :comments, class_name: "TodoComment", dependent: :destroy
  has_many :assignments, class_name: "TodoAssignment", dependent: :destroy
  has_many :assigned_agents, through: :assignments, source: :agent
  has_many :hosted_agent_sessions, as: :origin, dependent: :destroy
  has_many :reactions, as: :reactable, dependent: :destroy
  has_rich_text :description

  enum :status, { open: 0, completed: 1, in_progress: 2 }

  scope :ordered, -> { order(:position, :created_at) }

  validates :title, presence: true, length: { maximum: 160 }
  validate :parent_belongs_to_project

  def move_to!(parent:, position:)
    target_position = Integer(position)
    validate_move_parent!(parent)

    project.with_lock do
      reload
      validate_move_parent!(parent)
      old_parent = self.parent
      old_scope = old_parent ? old_parent.children : project.todos.roots
      new_scope = parent ? parent.children : project.todos.roots
      same_scope = old_parent == parent
      old_siblings = old_scope.where.not(id: id).ordered.to_a
      new_siblings = same_scope ? old_siblings.dup : new_scope.where.not(id: id).ordered.to_a
      target_position = target_position.clamp(0, new_siblings.length)

      self.parent = parent
      self.position = target_position
      save!

      old_siblings.each_with_index { |sibling, index| sibling.update_column(:position, index) } unless same_scope
      new_siblings.insert(target_position, self)
      new_siblings.each_with_index do |sibling, index|
        sibling.update_column(:position, index) unless sibling == self
      end
    end
  end

  private

  def validate_move_parent!(new_parent)
    if new_parent && new_parent.project_id != project_id
      errors.add(:parent, "must belong to the same project")
      raise ActiveRecord::RecordInvalid, self
    elsif new_parent == self || (new_parent && new_parent.ancestors.include?(self))
      errors.add(:parent, "cannot be nested below itself")
      raise ActiveRecord::RecordInvalid, self
    end
  end

  def parent_belongs_to_project
    errors.add(:parent, "must belong to the same project") if parent && parent.project_id != project_id
  end
end
