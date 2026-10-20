# == Schema Information
#
# Table name: groups
#
#  id         :integer          not null, primary key
#  name       :string(255)
#  created_at :datetime         not null
#  updated_at :datetime         not null
#

class Group < ActiveRecord::Base
  # attr_accessible :name
  has_many :group_users, :dependent => :destroy
  has_many :users, :through => :group_users
  
  validates( :name, :presence => true,
             :length => { :maximum => 50 },
             :uniqueness => { :case_sensitive => false } )
  
  scope :sorted, -> { order('name ASC') }
  
  #this function gives the report name, which is the group name without the report_ prefix
  def report_name
    name.sub('report_', '')
  end
  
  #returns whether a user is a member of the group
  def member?(user)
    group_users.find_by_user_id(user.id)
  end

  #function that allows the deleting of a user from a group
  def delete_user(user)
    users.delete user
  end
  
  #returns a list of all the users not in the group
  def users_not_in_group
    userids = userid_hash
    not_in_grp = Array.new
    User.all_activated.each do |user|
      not_in_grp << user if !userids.include?(user.id)
    end
    not_in_grp
  end

  def users_not_in(term)
    user_ids = users.pluck(:id)
    User.all.order(:name).where("name LIKE ?", "%#{term}%").where.not(id: user_ids).map { |x| { id: x.id, name: x.name } }
  end

  #hash of user ids to assist with users not in group creation, allowing for faster lookups
  def userid_hash
    userids = Hash.new
    users.each do |user|
      userids[user.id] = user.id
    end
    userids
  end
end
