# A tree is the unit an annotator works on: one kit's annotations all carry its
# tree_id, and replaying them gives the node graph (NodeDerivation).
#
# This model used to own an in-memory copy of that graph, built from a nodes
# table and "elaborated" with node classes, styles and types. The table is gone
# and the readers replay the log, so what's left is the row itself — its class
# def and uid — plus the node-class lookup NodeClass uses while building a root.
class Tree < ActiveRecord::Base
  # attr_accessible :class_def_id, :last_iid, :uid, :version
  has_many :kits
  belongs_to :class_def

  @@counter = "0" * 16

  def class_def_node_classes
    class_def.node_classes
  end

  def class_def_name
    class_def.name
  end

  def assign_id
    self.uid = ("%x" % Time.now.to_i) + @@counter.succ!
    raise "duplicate tree uid #{uid}" if Tree.find_by_uid uid
  end

  # Node classes by name and by id, cached per tree instance. Similar to eager
  # loading, but it doesn't *force* the load.
  def get_node_class(name)
    if @all_node_classes.nil?
      @all_node_classes = {}
      class_def_node_classes.each do |nc|
        @all_node_classes[nc.name] = nc
        @all_node_classes[nc.id] = nc
      end
    end
    if @all_node_classes[name].nil?
      nc = name.is_a?(String) ? NodeClass.find_by_name(name) : NodeClass.find(name)
      raise name if nc.nil?
      @all_node_classes[nc.name] = nc
      @all_node_classes[nc.id] = nc
    end
    @all_node_classes[name]
  end

  def grammar
    @grammar ||= class_def.get_grammar
  end

  def inverted_grammar
    @inverted_grammar ||= class_def.get_inverted_grammar
  end
end
