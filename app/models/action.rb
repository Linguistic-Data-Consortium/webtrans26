class Action < ApplicationRecord
  belongs_to :user
  belongs_to :task
  belongs_to :kit
end
