class CreateImportedGraphs < ActiveRecord::Migration[8.1]
  # An annotation graph that came from somewhere else: a reference transcript,
  # an ASR pass, a forced alignment. Same formalism as graph_nodes / graph_arcs
  # / graph_labels — anchors, spans between them, labels on the spans — without
  # the expansion the annotator side carries.
  #
  # That expansion (iid, user_id, task_id, and an annotations row per value)
  # records who did what and in which order. An import has no actions in it:
  # its provenance is one fact about the whole file, so it lives on the
  # container and the rows stay lean.
  #
  # Unlike the annotator side, these reference each other by row id rather than
  # by an iid scoped to a parent, so the database can index the joins.
  def change
    create_table :imported_graphs do |t|
      t.string :docid, null: false      # the document this is over; ':A'/':B' for a stereo kit
      t.string :name, null: false       # which tier: reference, asr, alignment
      t.string :source                  # where it came from
      t.string :format                  # how to read that: tsv, tdf, json
      t.string :content_hash            # of the imported bytes — tells a re-import from a no-op
      t.timestamps
      t.index [ :docid, :name ], unique: true
    end

    # One row per distinct time. The unique index is what makes anchors shared
    # rather than duplicated: a contiguous transcript needs N+1 of these, not
    # 2N, and tiers over the same timeline land on the same rows.
    create_table :imported_nodes do |t|
      t.integer :imported_graph_id, null: false
      t.decimal :time, precision: 12, scale: 6, null: false
      t.timestamps
      t.index [ :imported_graph_id, :time ], unique: true
    end

    create_table :imported_arcs do |t|
      t.integer :imported_graph_id, null: false
      t.string :name                    # Segment, Word, Turn, …
      t.integer :beg_node_id, null: false
      t.integer :end_node_id, null: false
      # The anchors carry the times; these are copies, so "what overlaps this
      # stretch of audio" is an indexed scan instead of a join through both
      # ends. Written only by the importer, which replaces the graph wholesale.
      t.decimal :beg, precision: 12, scale: 6
      t.decimal :end, precision: 12, scale: 6
      t.timestamps
      t.index [ :imported_graph_id, :beg ]
      t.index [ :imported_graph_id, :end ]
      t.index [ :imported_graph_id, :name ]
    end

    create_table :imported_labels do |t|
      t.integer :imported_arc_id, null: false
      t.integer :imported_graph_id, null: false   # denormalized: read or drop a whole graph's labels without a join
      t.string :name                    # Text, Speaker, Section, …
      t.text :value
      t.timestamps
      t.index [ :imported_arc_id, :name ]
      t.index :imported_graph_id
    end
  end
end
