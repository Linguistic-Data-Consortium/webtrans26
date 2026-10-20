class NodeClass < ActiveRecord::Base
  # attr_accessible :name, :parent_id, :children, :span, :style_id, :value, :class_def_id, :lazy
  belongs_to :parent, :class_name => 'NodeClass', optional: true
  belongs_to :class_def, optional: true
  delegate :name, :to => :parent, :prefix => true
  delegate :name, :css, :horizontal, :classes, :to => :style, :prefix => true
  delegate :name, :version, :to => :class_def, :prefix => true
  scope :root_nodes, -> { where(:parent_id => find_by_name('Root') ? find_by_name('Root').id : 1) }
  scope :sorted_root_nodes, -> { root_nodes.sorted }

  serialize :value, type: Hash
  serialize :constraints, type: Hash
  validates( :name, :presence => true,
             :uniqueness => { :case_sensitive => false }
             )

  scope :parent_nodes, -> { where(:parent_id => nil) }
  scope :sorted, -> { order('name ASC') }
  scope :sorted_parent_nodes, -> { parent_nodes.sorted }
  # these lines were added directly into LUI, there's some sort of load order connection problem
  #scope :root_nodes, where(:parent_id => find_by_name('Root') ? find_by_name('Root').id : 1)
  #scope :sorted_root_nodes, root_nodes.sorted
  scope :by_style_id, lambda{ |style_id| where(:style_id => style_id) }

  def label
    value['label']
  end

  def name_without_root_suffix
    name.gsub(":Root", "")
  end
  
  def name_without_prefix
    name.index(":") ? name[name.index(":")+1..-1] : name
  end
  
  def name_prefix
    name[0..name.index(":")-1]
  end
  
  def types
    type = self
    a = []
    while type != nil
      a << type.name #.sub(/.+:/, '')
      a << 'List' if type.name == 'EmbeddedList'
      type = type.parent
    end
    a << 'Node' unless a[-1] == 'Node'
    a
  end
  
  def get_children_map
    map = {}
    if children
      children.split(',').each do |x|
        a = x.split '.'
        map[a[0]] = a[1]
      end
    end
    map
  end
  
  def create_nodes(cname, num, user_id, task_id, tree, parent_id=nil, index=0)
    node = Node.new
    # puts 11
    node.name = cname
    # puts 22
    node.user_id = user_id
    # puts 33
    node.task_id = task_id
    node.tree_id = tree.id
    node.node_class_id = id
    # puts 44
    @node_type_string ||= "LDCI::NodeClasses::" + name.sub(':', '::')
    node.type = @node_type_string
    # puts 55
    if cname == 'Root'
      node.iid = '0'
    else
      node.iid = num.succ!.dup
    end
    # puts 66
    node.node_id = "#{tree.uid}-#{node.iid}"
    @is_node_list ||= types.include? 'List'
    node.list = @is_node_list
    # puts 77
    create_children num, node, user_id, task_id, tree
  end
  
  def create_children(num, node, user_id, task_id, tree)
    if @has_children.nil?
      if children and children.size > 0
        @has_children = true
        @child_array = children.split ','
        @child_array.each do |c|
          raise "'#{c}' is a reserved word" if c == 'children' or c == 'meta' or c == 'value'
        end
        @child_array.map! do |c|
          cname, type_name = c.split '.'
          cnode_class = tree.get_node_class type_name
          raise type_name if cnode_class.nil?
          [ cname, cnode_class ]
        end
      else
        @has_children = false
      end
    end

    # :children and :value are mutually exclusive
    if @has_children
      node.leaf = false
      node.children_nodes = []
      @child_array.each_with_index do |c, i|
        cname, cnode_class = c
        if (not node.list) or constraints['auto_add'] == 1
          # puts 'lazy1 ' + i.to_s
          cnode = cnode_class.create_nodes cname, num, user_id, task_id, tree, nil, i
          node.children_nodes << cnode.iid
        end
        node.child = cname if node.list
      end
    else
      node.leaf = true
      if @node_value_id.nil?
        node_value = case parent_name
                     when 'Entry'
                       {'value' => value['text']}
                     when 'Text', 'CustomText'
                       { 'docid' => nil, 'beg' => nil, 'end' => nil }
                     when 'Coref'
                       { 'type' => 'coref', 'groups' => {} }.merge value
                     when 'CheckboxGroup'
                       {'value' => []}
                     else
                       {'value' => nil}.merge value
                     end
        node.children_nodes = [] if name_without_prefix == "Root"#this call is necessary for the case where the last child is being deleted from the Root node, otherwise it will persist and cause errors

        nv = NodeValue.create( :value => node_value.to_yaml )
        @node_value_id = nv.id
        v2 = node.new_value @node_value_id, node_value
        v2.save
      end
      node.node_value_id = @node_value_id
    end
    node.node_value_id = 0 if node.node_value_id.nil?
    node.save!
    node
  end

  #function that creates the tree json formatted in the correct way for the jqtree plugin to interpret it
  def create_tree_hash
    if children
      childs = Array.new
      children.split(',').each do |c|
        name = c[c.index(".")+1..-1]
        childs << NodeClass.find_by_name(name).create_tree_hash
      end
      if name_without_prefix == "Root"
        return [{:label => name_without_prefix, :type => parent_name, :children => childs}]
      else
        return {:label => name_without_prefix, :type => parent_name, :children => childs}
      end
    else
      return {:label => name_without_prefix, :type => parent_name }
    end
  end

end
