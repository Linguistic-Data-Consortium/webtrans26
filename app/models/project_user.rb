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
  
  delegate :name, :to => :user, :prefix => true
           
  delegate :name, :to => :project, :prefix => true
end
