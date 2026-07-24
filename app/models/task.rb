class Task < ApplicationRecord
  include ActivityTrackable

  has_ancestry orphan_strategy: :restrict

  belongs_to :project
  belongs_to :task_list
  belongs_to :creator, class_name: "User"
  has_many :comments, class_name: "TaskComment", dependent: :destroy
  has_many :assignments, class_name: "TaskAssignment", dependent: :destroy
  has_many :agent_sessions, as: :context, dependent: :destroy
  has_many :assigned_agents, through: :assignments, source: :agent
  has_many :reactions, as: :reactable, dependent: :destroy
  has_rich_text :description
  before_validation :assign_default_task_list, on: :create
  before_validation :set_initial_activity, on: :create
  after_create_commit :register_creator_participation

  enum :status, { open: 0, completed: 1 }

  scope :ordered, -> { order(:position, :created_at) }

  validates :title, presence: true, length: { maximum: 160 }
  validate :task_list_belongs_to_project
  validate :parent_belongs_to_task_list

  def move_to!(task_list: self.task_list, parent:, position:)
    target_position = Integer(position)
    validate_move_target!(task_list, parent)

    project.with_lock do
      reload
      validate_move_target!(task_list, parent)
      old_parent = self.parent
      old_task_list = self.task_list
      old_scope = sibling_scope(old_task_list, old_parent)
      new_scope = sibling_scope(task_list, parent)
      same_scope = old_parent == parent && old_task_list == task_list
      old_siblings = old_scope.where.not(id: id).ordered.to_a
      new_siblings = same_scope ? old_siblings.dup : new_scope.where.not(id: id).ordered.to_a
      target_position = target_position.clamp(0, new_siblings.length)

      self.task_list = task_list
      self.parent = parent
      self.position = target_position
      save!
      descendants.update_all(task_list_id: task_list.id) if old_task_list != task_list

      old_siblings.each_with_index { |sibling, index| sibling.update_column(:position, index) } unless same_scope
      new_siblings.insert(target_position, self)
      new_siblings.each_with_index do |sibling, index|
        sibling.update_column(:position, index) unless sibling == self
      end
    end
  end

  private

  def set_initial_activity
    self.last_activity_at ||= Time.current
  end

  def register_creator_participation
    register_participant!(creator)
  end

  def assign_default_task_list
    self.task_list ||= parent&.task_list || project&.default_task_list
  end

  def sibling_scope(list, parent)
    parent ? parent.children : project.tasks.roots.where(task_list: list)
  end

  def validate_move_target!(new_task_list, new_parent)
    if new_task_list.project_id != project_id
      errors.add(:task_list, "must belong to the same project")
      raise ActiveRecord::RecordInvalid, self
    elsif new_parent && (new_parent.project_id != project_id || new_parent.task_list_id != new_task_list.id)
      errors.add(:parent, "must belong to the same project and task list")
      raise ActiveRecord::RecordInvalid, self
    elsif new_parent == self || (new_parent && new_parent.ancestors.include?(self))
      errors.add(:parent, "cannot be nested below itself")
      raise ActiveRecord::RecordInvalid, self
    end
  end

  def task_list_belongs_to_project
    errors.add(:task_list, "must belong to the same project") if task_list && task_list.project_id != project_id
  end

  def parent_belongs_to_task_list
    return unless parent
    return if parent.project_id == project_id && parent.task_list_id == task_list_id

    errors.add(:parent, "must belong to the same project and task list")
  end
end
