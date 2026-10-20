# What an imported arc says about the span it covers: one row per field the
# source carried. A transcript segment contributes Text, and Speaker and
# Section when the file has them; another tier contributes whatever it has,
# with no new columns.
#
# Points at the arc's row id — imported rows have no iid, so nothing here needs
# scoping by a parent to be unambiguous.
class ImportedLabel < ApplicationRecord
  belongs_to :imported_arc, optional: true
  belongs_to :imported_graph, optional: true

  scope :by_graph, ->(graph_id) { where(imported_graph_id: graph_id) }
  scope :for_arc, ->(arc_id) { where(imported_arc_id: arc_id) }
  scope :named, ->(name) { where(name: name) }

  def to_row = { id: id, arc_id: imported_arc_id, name: name, value: value }
end
