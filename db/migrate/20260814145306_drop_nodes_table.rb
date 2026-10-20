class DropNodesTable < ActiveRecord::Migration[8.1]
  # The node graph is replayed from the annotation log (NodeDerivation) — the
  # readers were switched over, then the writes stopped, and the table has been
  # sitting frozen and unread since. This drops it.
  #
  # Reversible only in shape: `down` recreates the table empty, since the rows
  # can't come back from the schema. They don't need to — the log they were
  # built from is untouched, and the code that rebuilt them is in git history
  # (see NodeDerivation.rebuild!, removed in the same commit as this migration).
  def up
    drop_table :nodes
  end

  def down
    create_table :nodes do |t|
      t.integer :annotation_id
      t.datetime :created_at, null: false
      t.integer :iid
      t.integer :index
      t.integer :level
      t.string :name
      t.integer :parent_id
      t.integer :parent_iid
      t.integer :task_id
      t.integer :tree_id
      t.datetime :updated_at, null: false
      t.integer :user_id
      t.index [ :annotation_id ]
      t.index [ :parent_id ]
      t.index [ :parent_iid ]
      t.index [ :tree_id, :iid ], unique: true
    end
  end
end
