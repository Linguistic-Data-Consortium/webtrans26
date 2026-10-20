class CreateGraphNodesAndArcs < ActiveRecord::Migration[8.1]
  # A second, parallel projection of the annotation log — alongside the
  # segments/sections one that Kit#snapshot writes — in annotation-graph shape:
  #
  #   graph_nodes  one row per "1:NListItem,2:N" add: a time anchor.
  #   graph_arcs   one row per add that spans two anchors and labels the span
  #                ("5:SegmentListItem,6:Arc,7:Text,8:Speaker",
  #                 "17:SectionListItem,18:Arc,19:Name").
  #
  # Both are rebuilt from the log by Kit#graph_snapshot, so nothing here is a
  # source of truth and either table can be dropped and regenerated.
  def change
    create_table :graph_nodes do |t|
      t.integer :tree_id, null: false
      t.integer :iid, null: false        # the NListItem
      t.integer :n_iid                   # its N child, which carries the time
      t.string :docid
      t.decimal :time, precision: 12, scale: 6
      t.timestamps
      t.index [ :tree_id, :iid ], unique: true
      t.index [ :tree_id, :time ]
    end

    create_table :graph_arcs do |t|
      t.integer :tree_id, null: false
      t.integer :iid, null: false        # the list item
      t.string :name                     # SegmentListItem, SectionListItem, …
      t.integer :arc_iid                 # its Arc child
      t.integer :beg_iid                 # anchors the Arc points at: graph_nodes.iid
      t.integer :end_iid
      t.text :text                       # Text child
      t.string :speaker                  # Speaker child
      t.string :label                    # Name child (a section's label)
      t.timestamps
      t.index [ :tree_id, :iid ], unique: true
      t.index [ :tree_id, :beg_iid ]
      t.index [ :tree_id, :end_iid ]
    end
  end
end
