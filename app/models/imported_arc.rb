# A span between two ImportedNodes: one row per segment, word, turn — whatever
# the imported tier holds. What the span *says* lives in ImportedLabel, so a
# transcript's text and speaker don't take columns here.
#
# `beg` and `end` repeat the anchors' times. The anchors are the identity; the
# copies are what range queries read, and the importer is the only writer.
class ImportedArc < ApplicationRecord
  belongs_to :imported_graph, optional: true
  belongs_to :beg_node, class_name: "ImportedNode", optional: true
  belongs_to :end_node, class_name: "ImportedNode", optional: true
  has_many :imported_labels, dependent: :delete_all

  scope :by_graph, ->(graph_id) { where(imported_graph_id: graph_id) }
  scope :named, ->(name) { where(name: name) }
  scope :in_time_order, -> { order(:beg, :id) }

  # Arcs touching the stretch [beg, end] — overlap, not containment, so a
  # segment running past either edge still comes back.
  scope :overlapping, ->(beg, fin) { where("beg < ? AND \"end\" > ?", fin, beg) }

  def labels = ImportedLabel.for_arc(id)

  # What this arc says, as a hash: { "Text" => "…", "Speaker" => "…" }.
  def label_values = labels.each_with_object({}) { |l, h| h[l.name] = l.value }

  def to_row
    {
      id: id, name: name,
      beg_node_id: beg_node_id, end_node_id: end_node_id,
      beg: beg&.to_f, end: self[:end]&.to_f
    }
  end
end
