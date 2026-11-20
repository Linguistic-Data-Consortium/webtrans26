# == Schema Information
#
# Table name: group_users
#
#  id         :integer          not null, primary key
#  group_id   :integer
#  user_id    :integer
#  created_at :datetime         not null
#  updated_at :datetime         not null
#

class GroupUser < ActiveRecord::Base
  # Membership of Portal Managers or Project Managers is a role, so every way of
  # adding or removing one is in the security log (SecurityEvent): the Groups
  # tab, an invite, the console.
  after_create  { SecurityEvent.record("group.added", user: user, group: group&.name) }
  after_destroy { SecurityEvent.record("group.removed", user: user, group: group&.name) }
  # attr_accessible :group_id, :user_id
  belongs_to :group
  belongs_to :user
  validates :group_id, :presence => true
  validates :user_id, :presence => true
  # One membership row per user per group, matching the unique index on
  # (group_id, user_id) so a duplicate is a validation error rather than a
  # RecordNotUnique from the database.
  validates :user_id, :uniqueness => { :scope => :group_id, :message => 'is already a member of this group' }


  delegate :name, :to => :user, :prefix => true
  delegate :name, :to => :group, :prefix => true
  
  scope :by_user, lambda{ |user_id| where(:user_id => user_id) }
end
