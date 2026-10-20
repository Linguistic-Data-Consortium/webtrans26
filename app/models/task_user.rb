# == Schema Information
#
# Table name: task_users
#
#  id         :integer          not null, primary key
#  task_id    :integer
#  user_id    :integer
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  state      :string(255)
#  node_id    :integer
#  admin      :boolean          default(FALSE)
#  meta       :text
#  kit_id     :integer
#  kit_oid    :string(255)
#

class TaskUser < ActiveRecord::Base
  # attr_accessible :task_id, :user_id, :state, :meta, :kit_id, :kit_oid
  serialize :meta, type: Hash
  belongs_to :task
  belongs_to :user
  has_many :task_user_states
  validates :task_id, :presence => true
  validates :user_id, :presence => true
  # One membership row per user per task, matching the unique index on
  # (task_id, user_id) so a duplicate is a validation error rather than a
  # RecordNotUnique from the database.
  validates :user_id, :uniqueness => { :scope => :task_id, :message => 'is already a member of this task' }

  scope :kit_taskuser, lambda{ |kitId| where(:kit_oid => kitId).limit(1) }
  scope :by_task, lambda{ |task_id| where(:task_id => task_id) }
  scope :by_user, lambda{ |user_id| where(:user_id => user_id) }
  scope :by_state, lambda{ |state| where(:state => state) }
  scope :by_negated_state, lambda{ |state| where('state != ?', state) }
  scope :by_task_and_user, lambda{ |task_id, user_id | by_task(task_id).by_user(user_id) }
  scope :by_task_and_state, lambda{ |task_id, state| by_task(task_id).by_state(state) }
  scope :by_task_and_negated_state, lambda{ |task_id, state| by_task(task_id).by_negated_state(state) }

  delegate :name, :lead_annotator?, :to => :user, :prefix => true

  delegate :name, :workflow_id, :workflow, :kit_type, :to => :task, :prefix => true
  delegate :project, :project_id, :to => :task

  has_paper_trail

  before_save :set_oid
  after_save :goto_state2

  def set_oid
    kit_oid = '' if state == 'needs_kit'
  end

  def goto_state(s)
    self.state = s
    save!
  end

  def goto_state2
    last = task_user_states.last
    if last and last.state != state
      TaskUserState.create(task_user_id: id, state: state)
    end
  end

  def project_admin?
    puser = ProjectUser.by_project_and_user(project_id, user_id).first
    if puser
      puser.admin? || puser.owner? || system_admin?
    else
      false
    end
  end

  def system_admin?
    user.admin?
  end

  def has_kit_oid?
    kit_oid && !kit_oid.empty?
  end

end
