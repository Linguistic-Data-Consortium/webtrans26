class AddStemToImportedGraphs < ActiveRecord::Migration[8.1]
  # What a document is called with the unpredictable parts taken off: no
  # directory, no extension, no channel suffix, lower case. A kit's source and
  # the id written in a transcript rarely agree about those, and matching on
  # what's left is how the two find each other.
  #
  # Stored rather than computed per lookup: a kit opening asks "is there an
  # imported graph for my audio?", and that shouldn't scan every row.
  class Graph < ActiveRecord::Base
    self.table_name = "imported_graphs"
  end

  def up
    add_column :imported_graphs, :stem, :string
    add_index :imported_graphs, [ :stem, :name ]

    Graph.reset_column_information
    Graph.transaction do
      Graph.where(stem: nil).pluck(:id, :docid).each do |id, docid|
        base = File.basename(docid.to_s.split(":").first.to_s)
        Graph.where(id: id).update_all(stem: base.sub(/\.[^.]+\z/, "").downcase)
      end
    end
  end

  def down
    remove_index :imported_graphs, [ :stem, :name ]
    remove_column :imported_graphs, :stem
  end
end
