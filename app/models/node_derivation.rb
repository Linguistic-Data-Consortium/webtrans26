# A tree's node graph, replayed from its annotation log.
#
# This is the only place the graph comes from. There used to be a nodes table,
# written row by row as each annotation was created; it was never a source of
# truth, since every row in it came from the log. Now the log is read directly
# and the table is gone (db/migrate/20260814145306_drop_nodes_table.rb).
#
#   NodeDerivation.for_tree(id)   — the graph for one tree
#   NodeDerivation.for_trees(ids) — several, in one query
#
# A derived node is a plain Hash carrying what the readers need:
#
#   { iid:, name:, parent_iid:, index:, level:, annotation_id:, user_id:, task_id: }
#
# There's no `parent_id`: that was the parent row's database id, and nothing
# reads it — work/other.js's init2 takes only name, iid, parent_iid, level and
# annotation_id.
module NodeDerivation
  Result = Struct.new(:nodes, :anomalies, :annotations_by_id, keyword_init: true) do
    # iid => node hash, in insertion order
    def count = nodes.size
    def ok? = anomalies.empty?

    # What Node#value would return for a derived node.
    def value_for(node)
      annotation = annotations_by_id[node[:annotation_id]]
      annotation ? annotation.node_value : Annotation::NO_VALUE.dup
    end

    # What Node#to_client_hash returned, for a derived node. `nid` (the node's
    # database id) is gone: nothing reads it — the client takes meta.name,
    # meta.id and value.
    def client_hash(node)
      { "meta" => { "name" => node[:name], "id" => node[:iid] }, "value" => value_for(node) }
    end

    # The annotations the nodes point at — the payload's node_values, without a
    # second trip to the database.
    def referenced_annotations
      nodes.values.map { |node| node[:annotation_id] }.uniq.filter_map { |id| annotations_by_id[id] }
    end
  end

  class << self
    # tree_id => Result for several trees, in one query rather than one each.
    def for_trees(tree_ids)
      tree_ids = tree_ids.compact.uniq
      return {} if tree_ids.empty?

      by_tree = Annotation.where(tree_id: tree_ids).order(:id).group_by(&:tree_id)
      placeholder = Annotation.find_by(id: 0)
      tree_ids.index_with do |tree_id|
        result = replay(by_tree[tree_id] || [])
        result.annotations_by_id[0] = placeholder if placeholder && references_placeholder?(result)
        result
      end
    end

    def for_tree(tree_id)
      result = replay(Annotation.where(tree_id: tree_id).order(:id))
      if references_placeholder?(result)
        placeholder = Annotation.find_by(id: 0)
        result.annotations_by_id[0] = placeholder if placeholder
      end
      result
    end

    # The fold. `annotations` must be ordered by id — that's the order in which
    # Annotation#apply ran, and later messages overwrite earlier ones.
    def replay(annotations)
      nodes = {}
      anomalies = []
      annotations = annotations.to_a

      annotations.each do |annotation|
        case annotation.message
        when "add"    then apply_add(annotation, nodes, anomalies)
        when "change" then apply_change(annotation, nodes, anomalies)
        when "delete" then apply_delete(annotation, nodes, anomalies)
        # 'new', 'done' and the rest never touched the nodes table.
        end
      end

      Result.new(nodes: nodes, anomalies: anomalies, annotations_by_id: annotations.index_by(&:id))
    end

    # Every tree the log knows about.
    def tree_ids
      Annotation.where.not(tree_id: nil).distinct.pluck(:tree_id).compact.sort
    end

    def references_placeholder?(result)
      result.nodes.each_value.any? { |node| node[:annotation_id] == 0 }
    end

    private

    # "12:SegmentListItem,13:Arc,14:Text,15:Speaker" — the first element is the
    # list item (level 2) and carries this annotation's value; the rest are its
    # children (level 3), which start out valueless and point at the id-0
    # placeholder until a 'change' arrives.
    def apply_add(annotation, nodes, anomalies)
      children = annotation.value.to_s.split(",")
      if children.empty?
        anomalies << "annotation #{annotation.id}: 'add' with no children (value #{annotation.value.inspect})"
        return
      end

      parent_iid = nil
      children.each_with_index do |child, i|
        iid_string, name = child.split(":")
        iid = iid_string.to_i
        if name.nil? || iid_string !~ /\A\d+\z/
          anomalies << "annotation #{annotation.id}: malformed child #{child.inspect}"
          next
        end
        if nodes.key?(iid)
          # The (tree_id, iid) unique index would have rejected this.
          anomalies << "annotation #{annotation.id}: iid #{iid} added twice"
        end

        nodes[iid] = {
          iid: iid,
          name: name,
          parent_iid: (i.zero? ? nil : parent_iid),
          index: (i.zero? ? nil : i - 1),
          level: (i.zero? ? 2 : 3),
          annotation_id: (i.zero? ? annotation.id : 0),
          user_id: annotation.user_id,
          task_id: annotation.task_id
        }
        parent_iid = iid if i.zero?
      end
    end

    # Repoints one node at this annotation; its value is then whatever that
    # annotation holds. The node keeps its place in the tree.
    def apply_change(annotation, nodes, anomalies)
      node = nodes[annotation.iid]
      if node.nil?
        anomalies << "annotation #{annotation.id}: 'change' for unknown iid #{annotation.iid.inspect}"
        return
      end
      node[:annotation_id] = annotation.id
      node[:user_id] = annotation.user_id
      node[:task_id] = annotation.task_id
    end

    # Takes the node and everything parented to it.
    def apply_delete(annotation, nodes, anomalies)
      iid = annotation.iid
      unless nodes.key?(iid)
        anomalies << "annotation #{annotation.id}: 'delete' for unknown iid #{iid.inspect}"
      end
      nodes.delete(iid)
      nodes.delete_if { |_, node| node[:parent_iid] == iid }
    end
  end
end
