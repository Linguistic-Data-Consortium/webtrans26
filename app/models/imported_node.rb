# A time anchor in an imported graph. The container holds the docid, so a node
# is a time and nothing else.
#
# One row per distinct time (enforced by a unique index): arcs that meet at a
# boundary share the anchor, and so do tiers over the same timeline.
class ImportedNode < ApplicationRecord
  belongs_to :imported_graph, optional: true

  scope :by_graph, ->(graph_id) { where(imported_graph_id: graph_id) }
  scope :in_time_order, -> { order(:time, :id) }

  def to_row = { id: id, time: time&.to_f }
end
