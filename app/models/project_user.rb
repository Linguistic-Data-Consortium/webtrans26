# == Schema Information
#
# Table name: project_users
#
#  id         :integer          not null, primary key
#  project_id :integer
#  user_id    :integer
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  admin      :boolean          default(FALSE)
#  owner      :boolean          default(FALSE)
#

class ProjectUser < ActiveRecord::Base
  # The security log (SecurityEvent), from here rather than each controller,
  # so every way in — the dashboard, invites, a task import, the console — is
  # recorded.
  after_create  { SecurityEvent.record("project_member.added", user: user, project: project&.name,
                                       owner: owner? || nil, admin: admin? || nil) }
  after_destroy { SecurityEvent.record("project_member.removed", user: user, project: project&.name) }
  after_update do
    if saved_change_to_owner? || saved_change_to_admin?
      SecurityEvent.record("project_role.changed", user: user, project: project&.name, owner: owner?, admin: admin?)
    end
  end
  # attr_accessible :project_id, :user_id, :admin
  belongs_to :project
  belongs_to :user
  validates :project_id, :presence => true
  validates :user_id, :presence => true
  # One membership row per user per project, matching the unique index on
  # (project_id, user_id) so a duplicate is a validation error rather than a
  # RecordNotUnique from the database.
  validates :user_id, :uniqueness => { :scope => :project_id, :message => 'is already a member of this project' }


  scope :by_project_and_user, lambda{ |project_id, user_id | where(:user_id => user_id, :project_id => project_id) }
  scope :project_owner, lambda{|project_id| where( :project_id => project_id, :owner => true)}
  
  # Whether this member may write to the project's S3 prefix.
  #
  # Reading follows membership of the project; writing also needs membership of
  # the project's upload task (Project#s3_upload_task). That membership is
  # granted the way any task membership is, by a task or project admin, so the
  # permission is something a higher role hands out rather than a role itself.
  #
  # The one place that decision lives: User#s3_write_project_ids and the
  # session policy both ask this. No upload task means nobody writes.
  def may_write_s3?
    task = project&.s3_upload_task
    task.present? && task.task_users.exists?(user_id: user_id)
  end

  delegate :name, :to => :user, :prefix => true
           
  delegate :name, :to => :project, :prefix => true
end
