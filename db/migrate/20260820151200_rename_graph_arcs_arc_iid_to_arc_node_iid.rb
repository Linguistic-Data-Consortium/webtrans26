class RenameGraphArcsArcIidToArcNodeIid < ActiveRecord::Migration[8.1]
  # Two columns were called arc_iid and meant different things:
  #
  #   graph_arcs.arc_iid    the group's Arc *child* — iid + 1 by the legacy
  #                         group layout, not the arc's own identity
  #   graph_labels.arc_iid  the arc row's iid, i.e. the list item
  #
  # The label side reads correctly (arcs are identified by iid), so only the
  # arc side moves: arc_node_iid says it holds a node's iid, not the arc's.
  #
  # graph_arcs is rebuilt from the annotation log by Kit#graph_snapshot, so a
  # plain rename is enough — nothing here is a source of truth.
  def change
    rename_column :graph_arcs, :arc_iid, :arc_node_iid
  end
end
