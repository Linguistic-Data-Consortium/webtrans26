class KitUser < ActiveRecord::Base
  # attr_accessible :kit_id, :status, :user_id
  belongs_to :kit
  belongs_to :user
end
