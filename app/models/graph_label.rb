# What an arc says about the span it covers: one row per non-Arc child of an add
# group. A SegmentListItem contributes Text and Speaker rows, a SectionListItem
# a Name row, and a class def with different children contributes whatever it
# has — the arc itself stays structural.
#
# Written by Kit#graph_snapshot alongside GraphNode and GraphArc.
#
# `arc_iid` is the arc row's `iid` (the list item this label hangs off), not
# that row's `arc_node_iid` — those name two different nodes.
class GraphLabel < ApplicationRecord
  belongs_to :tree, optional: true

  scope :by_tree, ->(tree_id) { where(tree_id: tree_id) }
  scope :for_arc, ->(arc_iid) { where(arc_iid: arc_iid) }
  scope :named, ->(name) { where(name: name) }

  def arc = GraphArc.find_by(tree_id: tree_id, iid: arc_iid)

  def to_row
    { iid: iid, arc_iid: arc_iid, name: name, value: value }
  end
end
