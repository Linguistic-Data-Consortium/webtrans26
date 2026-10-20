# A time anchor in the annotation graph: one row per "1:NListItem,2:N" group in
# the log. The NListItem is the anchor's identity, the N child carries the time.
#
# Written by Kit#graph_snapshot, which rebuilds the whole tree's rows — nothing
# here is a source of truth, and the annotations remain the record.
class GraphNode < ApplicationRecord
  belongs_to :tree, optional: true

  scope :by_tree, ->(tree_id) { where(tree_id: tree_id) }
  scope :in_time_order, -> { order(:time, :iid) }

  def to_row
    { iid: iid, n_iid: n_iid, docid: docid, time: time&.to_f }
  end
end
