class Source < ApplicationRecord
  # has_one_attached :file
  belongs_to :user, optional: true
  belongs_to :task, optional: true
end
