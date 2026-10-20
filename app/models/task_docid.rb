# One document on a task's list — the list every user of that task is given,
# a kit at a time, by the SameListForEveryone workflow.
#
# The docid is what a kit's source_uid will be, so it's whatever that task's
# kits use: an s3:// url, a path, a bare id.
class TaskDocid < ApplicationRecord
  belongs_to :task, optional: true

  scope :for_task, ->(task_id) { where(task_id: task_id) }
  scope :in_order, -> { order(:position, :id) }

  # Replace a task's whole list with these docids, in this order. Wholesale,
  # because the list is a list: reconciling it row by row would leave an order
  # that matches neither what was there nor what was typed.
  #
  # Blank lines and repeats go; whitespace around a docid goes. Returns the
  # rows as they now stand.
  def self.replace_for(task_id, docids)
    wanted = Array(docids).map { |d| d.to_s.strip }.reject(&:empty?).uniq
    transaction do
      for_task(task_id).delete_all
      now = Time.zone.now
      if wanted.any?
        insert_all(wanted.each_with_index.map { |docid, i|
          { task_id: task_id, docid: docid, position: i, created_at: now, updated_at: now }
        })
      end
    end
    for_task(task_id).in_order
  end

  # The list as typed into a textarea: one docid per line.
  def self.text_for(task_id) = for_task(task_id).in_order.pluck(:docid).join("\n")
end
