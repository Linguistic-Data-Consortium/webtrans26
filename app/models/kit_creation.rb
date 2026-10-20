class KitCreation < ActiveRecord::Base
  belongs_to :kit_batch
  belongs_to :kit, optional: true
  belongs_to :user, optional: true
  belongs_to :task, optional: true
  validates :input, presence: true
  validates :task_id, presence: true
  validates :kit_batch_id, presence: true
end
