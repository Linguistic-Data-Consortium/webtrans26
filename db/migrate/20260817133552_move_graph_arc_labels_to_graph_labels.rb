class MoveGraphArcLabelsToGraphLabels < ActiveRecord::Migration[8.1]
  # graph_arcs carried text and speaker (a segment's labels) alongside label (a
  # section's), which put two different things in one row's columns. An arc is
  # just a span between two anchors; what's said about that span is a separate
  # thing, and there can be any number of them.
  #
  # So: arcs keep their structure, and every non-Arc child of the add group
  # becomes a graph_labels row. A class def whose list items carry different
  # children needs no new columns.
  #
  # Both tables are rebuilt from the annotation log by Kit#graph_snapshot, so
  # there's nothing to migrate — the next rebuild refills them.
  def change
    remove_column :graph_arcs, :text, :text
    remove_column :graph_arcs, :speaker, :string
    remove_column :graph_arcs, :label, :string

    create_table :graph_labels do |t|
      t.integer :tree_id, null: false
      t.integer :arc_iid, null: false   # the list item the label belongs to
      t.integer :iid, null: false       # the label node itself
      t.string :name                    # Text, Speaker, Name, …
      t.text :value
      t.timestamps
      t.index [ :tree_id, :iid ], unique: true
      t.index [ :tree_id, :arc_iid ]
    end
  end
end
