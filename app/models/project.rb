# == Schema Information
#
# Table name: projects
#
#  id         :integer          not null, primary key
#  name       :string(255)
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  s3_upload_task_id :integer
#

class Project < ActiveRecord::Base
  # attr_accessible :name

  validates( :name, :presence => true,
  :uniqueness => { :case_sensitive => false })
  # Names were once joined into filesystem paths; keep them unable to be one.
  validates :name, format: { without: %r{[/\\]|\.\.|[[:cntrl:]]}, message: "can't contain slashes, '..' or control characters" }

  has_many :project_users, :dependent => :destroy
  has_many :users, :through => :project_users
  has_many :tasks, :dependent => :destroy
  has_many :collections
  has_many :compensations
  has_many :task_type_users

  # The task whose members may write to this project's S3 prefix — see
  # ProjectUser#may_write_s3? and aws/s3_project_prefixes.md. None means
  # nobody may, which is the safe default for a permission nobody has granted.
  belongs_to :s3_upload_task, class_name: 'Task', optional: true
  validate :s3_upload_task_in_this_project

  # The task whose members may download this project's work: transcripts and
  # table exports (#may_download?). None by default, so only system admins can.
  belongs_to :download_task, class_name: 'Task', optional: true
  validate :download_task_in_this_project

  scope :sorted, -> { order('name ASC') }
  scope :all_newest_first, -> { order('created_at DESC') }

  # Whether +user+ may use the download features for this project's work.
  # System admins always; anyone else only as a member of the download task.
  # The one place this is decided: the task view, the editor and the docs ask it.
  def may_download?(user)
    return false unless user
    return true if user.admin?
    download_task.present? && download_task.task_users.exists?(user_id: user.id)
  end

  #function that allows the deleting of a user from a project
  # Destroyed, not deleted, so the membership's callbacks run (the security
  # log records the removal).
  def delete_user(user)
    project_users.where(user_id: user.id).destroy_all
  end

  #returns whether a user is a member of the project
  def member?(user)
    find_project_user(user.id)
  end

  #returns whether a user is the owner of the project
  def owner?(user)
    puser = find_project_user(user.id)
    !puser.nil? ? puser.owner? : false
  end

  #returns whether a user is an admin of the project
  def admin?(user)
    puser = find_project_user(user.id)
    !puser.nil? ? puser.admin? : false
  end

  #returns the project user object for a user
  def find_project_user(user_id)
    project_users.find_by_user_id(user_id)
  end

  #returns a list of all the users not in the project
  def users_not_in_project
    userids = userid_hash
    not_in_proj = Array.new
    User.all_activated.each do |user|
      not_in_proj << user if !userids.include?(user.id)
    end
    not_in_proj
  end

  #hash of user ids to assist with users not in project creation, allowing for faster lookups
  def userid_hash
    userids = Hash.new
    users.each do |user|
      userids[user.id] = user.id
    end
    userids
  end

  private

  def download_task_in_this_project
    return if download_task_id.nil?
    unless download_task && download_task.project_id == id
      errors.add(:download_task, "must be a task in this project")
    end
  end

  # A task from another project would grant write access to this project's
  # prefix on the strength of membership somewhere else.
  def s3_upload_task_in_this_project
    return if s3_upload_task_id.nil?
    unless s3_upload_task && s3_upload_task.project_id == id
      errors.add(:s3_upload_task, "must be a task in this project")
    end
  end

  public

  #returns the user.name of the project owner
  def owner_name
    owner = ProjectUser.project_owner(id).first
    owner ? owner.user_name : "None"
  end
end
