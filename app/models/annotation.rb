# Annotations are the log: an append-only record of every add, change and
# delete made to a tree. They used to have a side effect — #apply wrote and
# repointed rows in the nodes table as each annotation was created — but the
# readers now replay this log instead (NodeDerivation), so creating an
# annotation writes nothing else.
class Annotation < ApplicationRecord

  # A node whose annotation_id is 0 (the placeholder row db/seeds.rb creates)
  # has no value of its own.
  NO_VALUE = { value: nil }.freeze

  # The value a node pointing at this annotation carries. Which columns are
  # populated decides the shape. This is the branching Node#get_value has always
  # done, moved here so a value can be read straight off the annotation, with no
  # Node row involved.
  def node_value
    if source_id
      { source_id: source_id }
    elsif text
      {
        docid: docid,
        beg: begi,
        end: endi,
        text: text
      }
    elsif begi and endi
      {
        beg: begi,
        end: endi
      }
    elsif begr and endr.nil?
      {
        docid: docid,
        beg: begr.to_f
      }
    elsif begr
      h = {
        docid: docid,
        beg: begr.to_f,
        end: endr.to_f
      }
      h[:value] = value if value
      h
    else
      { value: value }
    end
  end


end
