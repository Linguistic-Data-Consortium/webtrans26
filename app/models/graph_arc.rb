# A span between two GraphNodes: one row per add group that isn't an anchor —
# "5:SegmentListItem,6:Arc,7:Text,8:Speaker" or
# "17:SectionListItem,18:Arc,19:Name". The Arc child names the two anchors it
# spans; what's *said* about the span lives in GraphLabel, so a segment's text
# and speaker and a section's name don't share columns here.
#
# Written by Kit#graph_snapshot alongside GraphNode and GraphLabel.
#
# `iid` is the arc's own identity — the list item, and what a GraphLabel's
# `arc_iid` points at. `arc_node_iid` is the group's Arc child, a different
# node (iid + 1 by the legacy group layout).
class GraphArc < ApplicationRecord
  belongs_to :tree, optional: true

  scope :by_tree, ->(tree_id) { where(tree_id: tree_id) }
  scope :segments, -> { where(name: "SegmentListItem") }
  scope :sections, -> { where(name: "SectionListItem") }

  # The anchors this arc spans, when they've been written.
  def beg_node = GraphNode.find_by(tree_id: tree_id, iid: beg_iid)
  def end_node = GraphNode.find_by(tree_id: tree_id, iid: end_iid)

  def labels = GraphLabel.by_tree(tree_id).for_arc(iid)

  def to_row(times = {})
    {
      iid: iid,
      name: name,
      arc_node_iid: arc_node_iid,
      beg_iid: beg_iid,
      end_iid: end_iid,
      beg: times[beg_iid],
      end: times[end_iid]
    }
  end
end
