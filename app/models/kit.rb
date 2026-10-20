class Kit < ActiveRecord::Base
  # attr_accessible :meta, :user_id, :task_id, :kit_type_id, :uid, :state, :source, :broken_comment, :tree_id
  # attr_accessible :kit_batch_id, :not_user_id, :time_spent
  belongs_to :tree, optional: true
  belongs_to :user, optional: true
  belongs_to :task, optional: true
  belongs_to :kit_type, :class_name => 'KitType', optional: true
  belongs_to :kit_batch, optional: true
  belongs_to :not_user, :class_name => 'User', optional: true
  has_many :kit_stats
  has_many :kit_values
  has_many :kit_states
  delegate :name, :to => :user, :prefix => true

  serialize :meta, type: Hash
  serialize :source, type: Hash

  scope :assigned_by_task, lambda { |t| where( :state => 'assigned', :task_id => t ) }
  scope :unassigned_by_task, lambda { |t| where( :state => 'unassigned', :task_id => t ) }
  scope :unassigned_by_task_and_user, lambda { |t, u| where( :state => 'unassigned', :task_id => t, :user_id => u ) }
  scope :find_by_task, lambda { |task_id| where :task_id => task_id }

  # attr_accessor :source_type, :source_uid

  def editor
    meta['editor']
  end
  def editor=(arg)
    meta['editor'] = arg
  end

  @@counter = "0" * 16

  def meta
    @meta ||= {}
    @meta
  end

  [ :js, :source_transform, :unmapped_infoboxes, :root, :type,
    :workflow_id, :read_only, :parent, :task_user_id, :quality_control, :update_root, :view,
    :namestring, :es_kit, :existing_slots, :refdoc, :review, :lang, :slot, :query, :speaker,
    :empty_list, :coref_groups, :bootstrap_mode ].each do |sym|
    define_method(sym) do
      meta[sym.to_s]
    end

    define_method("#{sym}=") do |value|
      meta[sym.to_s] = value
    end
  end



  after_save :goto_state

  def goto_state
    last = kit_states.last
    if last.nil? or last.state != state
      KitState.create(kit_id: id, state: state)
      task.workflow.after_done self if state == 'done' and kit_states.where(state: :done).count == 1
    end
  end

  def kbptype
    meta['type']
  end

  def kbptype=(type)
    meta['type'] = type
  end

  def assign_id
    uid = ("%x" % Time.now.to_i) + @@counter.succ!
    while Kit.find_by_uid(uid)
      uid = ("%x" % Time.now.to_i) + @@counter.succ!
    end
    uid
  end

  def requeue
    Kit.transaction do
      reload
      if state == 'unassigned'
        update( uid: assign_id )
      end
    end
  end

  def initialize(*args)
    super
    self.uid = assign_id
  end

  def self.from_hash(h)
    kit = Kit.new
    case h['type']
    when /(person|gpe|org)/
      kit.kbptype = $1
      kit.fields_from_hash h, [ :namestring, :es_kit, :existing_slots, :refdoc, :unmapped_infoboxes, :slot, :query ]
      kit
    end

    kit.from_hash h unless kit.class == Kit

    #hack for kbp assessment
    kit.fields_from_hash h, [ :entity_slot, :slot, :query  ] if h['task_id'] == 75

    kit.id = h['_id']

    kit.fields_from_hash h, [ :tree, :state, :kit_type_id, :js, :root, :task_id, :user_id, :broken_comment,
                              :empty_list, :coref_groups, :type, :source_transform, :bootstrap_mode  ]

    #adding support for document display in legacy tools that used docid for the source
    if h.include? 'docid'
      kit.source = { 'type' => 'document', 'transform' => false, 'id' => h['docid'], 'media' => 'text' }
    else
      kit.source = h['source']
    end
    kit
  end

    # change to to to_interchange?
    # nodes_from: :log builds the tree section by replaying the annotations;
    # :graph builds the same section out of graph_nodes / graph_arcs /
    # graph_labels instead, for checking one against the other. Everything else
    # in the payload is kit and tree metadata, identical either way.
    def to_hash(mongo=false, depth='shallow', test=false, nodes_from: :log)
      # return { refresh: true }
      h = {}
      h['_id'] = uid unless uid.nil?
      if tree_id
        if mongo
          h['tree'] = tree.uid
          if h['tree'].class == String and h['tree'].length == 0
            h.delete 'tree'
          end
        else
          # Trees used to come in two shapes, and the other one was assembled
          # from a nodes table that no longer exists. Every tree is this one.
          h['tree'] = { meta: { id: '0' } }
          h['original_id'] = tree.version
          # No grammar here. Which groups exist and what each is made of is the
          # tool's business — it composes the "add" strings — and the server
          # only ever reflected a fixed table back at it. What arrives in the
          # log is replayed and projected structurally, whatever the names are.
          # See app/javascript/lib/ldcjs/waveform/groups.js.
          h.merge!(tree_section(nodes_from))
          h['payload_source'] = nodes_from.to_s
        end
      end

      if depth == 'deep'
        #when a source exists, get the content and the metadata from the uget server with access to that content
        case source
        when Hash
          case source['type']
          when 'multi_post'
            file = LDC::Resources::WebMultiPost.find_by_uid(source['uid']).raw_text
            media = source['media'] ? source['media'] : 'normal'
            source.merge! LDCI::Document.new(source['id'], file, source['transform'], media).get_hash
            source['type'] = source[:type] = 'multi_post'
          when 'document'
            file = LDCI.uget( { :uid =>  source['id'], :type => source['type'], :level => 1 }.to_json )['string']
            media = source['media'] ? source['media'] : 'normal'
            source.merge! LDCI::Document.new(source['id'], file, source['transform'], media).get_hash
          when 'conversation'
            begin
              file = LDCI.uget( { :id =>  source['id'], :type => source['type'], :transform_message_content => source['transform'] }.to_json )
              source.merge! file
            rescue JSON::ParserError
              puts "Failed to parse JSON returned from uget for input: #{h['source']}"
            end
          end
        end
      end


      # h['source'] = {
      #   'id' => KitValue.where(kit_id: self.id, key: 'source_uid').first.value,
      #   # 'transform' => source['transform'], #"false",
      #   # 'media' => source['media'], #'text',
      #   'type' => KitValue.where(kit_id: self.id, key: 'source_type').first.value
      # }
      s = if source[:uid]

        Source.where(uid: source[:uid]).first
      elsif source[:id]
        Source.where(id: source[:id]).first
      else
        nil
      end
      h['source'] = if s
        { uid: s.uid, id: s.uid }
      elsif source_uid
        { uid: source_uid, id: source_uid }
      else
        {}
      end
      h['filename'] = source[:filename] if source[:filename]
      

      atts = [ :js, :source_transform, :kit_type_id, :broken_comment, :task_id, :root, :workflow_id, :read_only, :parent,
               :task_user_id, :quality_control, :state, :view, :meta, :done_comment ]

      h['type'] = case kbptype
                  when /(person|org|gpe)/
                    atts.concat [ :namestring, :es_kit, :existing_slots, :refdoc, :unmapped_infoboxes ]
                    kbptype
                  end
      atts.concat [ :empty_list, :coref_groups, :user_id ] # :update_root, :kit_type, :lang, :review
      h.delete 'type' if h['type'].nil?
      atts.concat [ :slot, :query ] if task_id == 75
      atts << :bootstrap_mode
      atts.each do |sym|
        value = send(sym)
        h[sym.to_s] = value unless value.nil?
      end
      # but why?
      # ann = Annotation.where(kit_id: id).last
      # h['last_annotation_time'] = ann ? ann.created_at.to_i * 1000 : false
      time = Annotation.where(kit_id: id).maximum(:created_at)
      h['task_name'] = task.name
      h['last_annotation_time'] = time ? time.to_i * 1000 : false
      h['data_set_id'] = task.data_set_id
      h['kit_id'] = id
      if tree.respond_to? 'class_def'
        h['constraints'] = {}
      end
      h
    end

    def to_simple_hash
      # return { refresh: true }
      h = {}
      h['_id'] = uid unless uid.nil?

      s = if source[:uid]

        Source.where(uid: source[:uid]).first
      elsif source[:id]
        Source.where(id: source[:id]).first
      else
        nil
      end
      h['source'] = if s
        { uid: s.uid, id: s.uid }
      elsif source_uid
        { uid: source_uid, id: source_uid }
      else
        {}
      end
      h['filename'] = source[:filename] if source[:filename]
      

      atts = [ :kit_type_id, :broken_comment, :task_id, :root, :workflow_id, :read_only, :parent,
               :task_user_id, :state, :view, :meta, :done_comment, :user_id ]

      atts.each do |sym|
        value = send(sym)
        h[sym.to_s] = value unless value.nil?
      end
      # but why?
      # ann = Annotation.where(kit_id: id).last
      # h['last_annotation_time'] = ann ? ann.created_at.to_i * 1000 : false
      time = Annotation.where(kit_id: id).maximum(:created_at)
      h['last_annotation_time'] = time ? time.to_i * 1000 : false
      h['data_set_id'] = task.data_set_id
      h['kit_id'] = id
      h
    end

  def fields_from_hash(h, fields)
    h.each_key do |attr|
      raise RuntimeError, "Hash key #{attr} is not a string" if attr != attr.to_s
    end
    fields.each do |sym|
      if h.key?(sym.to_s)
        send("#{sym}=", h[sym.to_s])
      end
    end
    self
  end

  def reset
    tree_oid = nil
    @tree = nil
  end

  def blocked_for_user_id?(user_id)
    KitUser.where( kit_id: id, user_id: user_id ).count > 0
  end

  def create_tree(task_user)
    root = kit_type.new_root self, task_user
    if root.class == Tree
      update( tree_id: root.id )
    else
      update( tree_id: root.tree_id )
    end
  end

  def class_def
    # n = NodeClass.find(kit_type.node_class_id).name.split(':').first
    # ClassDef.find 2
    # ClassDef.find_by_name 'ArcTranscription'
    ClassDef.where(name: kit_type.node_class.name.split(':').first).first_or_create
  end


  # The tree as the client wants it: [ nodes, annotations they point at ].
  # Derived from the annotation log unless DERIVED_NODES=false, in which case
  # the nodes table is read as before. work/other.js's init2 reads name, iid,
  # parent_iid, level and annotation_id off each node and nothing else.
  def client_nodes
    derived = NodeDerivation.for_tree(tree_id)
    [ derived.nodes.values, derived.referenced_annotations ]
  end

  # Node name / iid / parent_iid / value for everything in the tree, in the
  # shape #snapshot needs.
  def snapshot_nodes
    derived = NodeDerivation.for_tree(tree_id)
    derived.nodes.values.map do |node|
      { iid: node[:iid], name: node[:name], parent_iid: node[:parent_iid], value: derived.value_for(node) }
    end
  end

  def snapshot
    # A kit that has never been opened has no tree — Task#create_default_kit
    # makes the kit row and leaves tree_id nil until someone works on it. There
    # are no nodes to snapshot, so there's nothing to do; without this, callers
    # that snapshot every kit in a task (KitsController#all) blow up on the
    # first unopened one.
    return if tree.nil?

    nodes = {}
    Segment.where(tree_id: tree_id).destroy_all
    Section.where(tree_id: tree_id).destroy_all
    %w[ NListItem N SegmentListItem Arc Text Speaker SectionListItem Name ].each do |x|
      nodes[x] = {}
    end
    snapshot_nodes.each do |node|
      n = { node: node }
      nodes[node[:iid]] = n
      # A group the client invented — a comment span, say — has no bucket here,
      # and shouldn't need one: this projection is the readable transcript, and
      # it exports segments and sections. Collect it and ignore it. Without the
      # default, an unknown name raised on nil, which would take down the
      # dashboard and the downloads for every kit in the task, not just the one
      # holding the new group. graph_nodes / graph_arcs / graph_labels are the
      # projection that carries anything.
      (nodes[node[:name]] ||= {})[node[:iid]] = n
    end
    nodes['N'].values.each do |x|
      n = x[:node]
      nodes[n[:parent_iid]][:n] = n[:value][:beg]
    end
    nodes['Arc'].values.each do |x|
      n = x[:node]
      name = nodes[n[:parent_iid]][:arc] = n[:value]
    end
    nodes['Text'].values.each do |x|
      n = x[:node]
      nodes[n[:parent_iid]][:text] = n[:value][:value]
    end
    nodes['Speaker'].values.each do |x|
      n = x[:node]
      nodes[n[:parent_iid]][:speaker] = n[:value][:value]
    end
    nodes['Name'].values.each do |x|
      n = x[:node]
      nodes[n[:parent_iid]][:name] = n[:value][:value]
    end
    nodes['SegmentListItem'].each do |k, v|
      n = v[:node]
      arc = v[:arc]
      if arc.nil?
        raise nodes['SegmentListItem'].to_s
      end
      Segment.create(
        tree_id: tree_id,
        iid: k,
        begn: arc[:beg],
        endn: arc[:end],
        btime: nodes[arc[:beg]][:n],
        etime: nodes[arc[:end]][:n],
        text: v[:text],
        speaker: v[:speaker]
      )
    end
    nodes['SectionListItem'].each do |k, v|
      n = v[:node]
      arc = v[:arc]
      Section.create(
        tree_id: tree_id,
        iid: k,
        begn: arc[:beg],
        endn: arc[:end],
        btime: nodes[arc[:beg]][:n],
        etime: nodes[arc[:end]][:n],
        name: v[:name]
      )
    end
  end

  # A second projection of the same log, in annotation-graph shape, written
  # alongside the segments/sections one that #snapshot builds. Rebuilds this
  # tree's rows from scratch, exactly as #snapshot does, and returns them for
  # display.
  #
  # An "add" message names a group of nodes at once — "1:NListItem,2:N" or
  # "5:SegmentListItem,6:Arc,7:Text,8:Speaker". A group whose child is an N is
  # an anchor (GraphNode); any other group is a span between two anchors
  # (GraphArc), and each of its remaining children is something said about that
  # span (GraphLabel). Segments and sections are the same shape here — an arc
  # plus its labels — rather than two sets of columns in one table.
  # The graph the log describes, as plain rows, without touching the database.
  # Each "add" group becomes one row: an anchor if it has an N child, otherwise
  # a span plus one row per label.
  #
  # Both graph paths start here — #graph_snapshot persists these rows, and the
  # client payload can be built from them directly (nodes_from: :graph_memory).
  def graph_projection
    return { nodes: [], arcs: [], labels: [] } if tree.nil?

    derived = NodeDerivation.for_tree(tree_id)
    groups = derived.nodes.each_value.group_by { |node| node[:parent_iid] || node[:iid] }
    nodes = []
    arcs = []
    labels = []

    groups.each do |list_item_iid, members|
      item = members.find { |m| m[:iid] == list_item_iid }
      next if item.nil? # a child whose list item was deleted out from under it
      children = members.reject { |m| m[:iid] == list_item_iid }
      child = ->(name) { children.find { |c| c[:name] == name } }
      value = ->(node) { node && derived.value_for(node) }

      if (n = child.call("N"))
        # "1:NListItem,2:N" — an anchor. The N carries docid + one time.
        v = value.call(n) || {}
        nodes << { iid: list_item_iid, n_iid: n[:iid], docid: v[:docid], time: v[:beg] }
      else
        # Everything else spans two anchors...
        arc = child.call("Arc")
        arc_value = value.call(arc) || {}
        arcs << {
          iid: list_item_iid,
          name: item[:name],
          arc_node_iid: arc && arc[:iid],
          beg_iid: arc_value[:beg],
          end_iid: arc_value[:end]
        }
        # ...and every other child says something about that span. Text and
        # Speaker for a segment, Name for a section, whatever a different class
        # def declares. A label's arc_iid is the arc's own iid — the list item —
        # not the arc's arc_node_iid.
        children.each do |c|
          next if c[:name] == "Arc"
          labels << {
            iid: c[:iid],
            arc_iid: list_item_iid,
            name: c[:name],
            value: (value.call(c) || {})[:value]
          }
        end
      end
    end

    { nodes: nodes, arcs: arcs, labels: labels }
  end

  # Writes that projection into graph_nodes / graph_arcs / graph_labels,
  # replacing this tree's rows, and returns what was stored. The persisted form
  # is what the Graph panel shows and what the graph payload route reads — the
  # long way round, kept deliberately so the stored rows can be checked against
  # the in-memory ones.
  def graph_snapshot
    return { nodes: [], arcs: [], labels: [] } if tree.nil?

    # Stamped from before the replay rather than from whenever each row happens
    # to be inserted, because what the timestamp has to mean is "these rows are
    # the log as of here". An annotation written while the rows were being
    # built is not in them; stamping afterwards would date the rows later than
    # that annotation and #graph_current? would call them fresh for ever.
    as_of = Time.current
    projection = graph_projection
    stamp = { tree_id: tree_id, created_at: as_of, updated_at: as_of }

    GraphNode.transaction do
      GraphNode.by_tree(tree_id).delete_all
      GraphArc.by_tree(tree_id).delete_all
      GraphLabel.by_tree(tree_id).delete_all

      projection[:nodes].each { |n| GraphNode.create!(n.merge(stamp)) }
      projection[:arcs].each { |a| GraphArc.create!(a.merge(stamp)) }
      projection[:labels].each { |l| GraphLabel.create!(l.merge(stamp)) }
    end

    graph_rows
  end

  # When this tree's stored rows were replayed, and when it was last annotated.
  # The pair is what says whether a snapshot is worth redoing.
  def graph_snapshot_at
    [ GraphNode, GraphArc, GraphLabel ]
      .filter_map { |model| model.by_tree(tree_id).maximum(:created_at) }.max
  end

  def last_annotated_at
    Annotation.where(tree_id: tree_id).maximum(:created_at)
  end

  # Whether the stored rows already say what a fresh replay would.
  #
  # Sound because `annotations` is append-only — nothing in the app updates or
  # destroys one — so the newest annotation is the whole of what could have
  # changed since. Strictly newer, not equal: a row stamped at the same instant
  # as an annotation may or may not have included it.
  #
  # A tree that has been annotated but has no rows to show for it — only `new`
  # and `done`, say — reads as stale every time. It replays two messages and
  # writes nothing, which is cheaper than a column to remember it by.
  def graph_current?
    return false if tree_id.nil?

    written = graph_snapshot_at
    return false if written.nil?

    annotated = last_annotated_at
    annotated.nil? || annotated < written
  end

  # The same question for many kits at once, in four queries rather than four
  # per kit — what Task#graph_snapshot asks before deciding what to rebuild.
  # Returns tree_id → true when the stored rows are already current.
  def self.graph_current_by_tree(tree_ids)
    tree_ids = tree_ids.compact.uniq
    return {} if tree_ids.empty?

    annotated = Annotation.where(tree_id: tree_ids).group(:tree_id).maximum(:created_at)
    written = [ GraphNode, GraphArc, GraphLabel ].each_with_object({}) do |model, out|
      model.where(tree_id: tree_ids).group(:tree_id).maximum(:created_at).each do |tree_id, at|
        out[tree_id] = at if out[tree_id].nil? || at > out[tree_id]
      end
    end

    tree_ids.index_with do |tree_id|
      at = written[tree_id]
      !at.nil? && (annotated[tree_id].nil? || annotated[tree_id] < at)
    end
  end

  # The persisted graph, ready for display: anchors in time order, then spans
  # with their anchors' times filled in, then what each span is labelled with.
  def graph_rows
    nodes = GraphNode.by_tree(tree_id).in_time_order.to_a
    times = nodes.each_with_object({}) { |n, h| h[n.iid] = n.time&.to_f }
    {
      nodes: nodes.map(&:to_row),
      arcs: GraphArc.by_tree(tree_id).order(:iid).map { |a| a.to_row(times) },
      labels: GraphLabel.by_tree(tree_id).order(:arc_iid, :iid).map(&:to_row)
    }
  end

  # The part of the client payload that describes the tree: its nodes, the
  # values they point at, and the highest iid handed out so far.
  #
  # :log replays the annotations (what the editor is served). :graph reads the
  # projection in graph_nodes / graph_arcs / graph_labels instead, so the two
  # can be compared for a kit whose snapshot is up to date. The graph tables
  # don't record which annotation gave a node its value, so the :graph form
  # keys values by the node's own iid and carries the graph row ids alongside —
  # it holds everything the :log form does, plus arc_node_iid.
  def tree_section(from = :log)
    case from
    when :graph        then graph_tree_section        # read back what a snapshot stored
    when :graph_memory then graph_memory_tree_section # built from the log, nothing written
    else                    log_tree_section
    end
  end

  def log_tree_section
    nodes, annotations = client_nodes
    {
      "nodes" => nodes,
      "node_values" => annotations.map do |x|
        {
          id: x.id,
          value: x.value,
          docid: x.docid,
          beg: (x.begi || x.begr.to_f),
          end: (x.endi || x.endr.to_f),
          text: x.text,
          source_id: x.source_id
        }
      end,
      "last_iid" => last_add_iid
    }
  end

  def last_add_iid
    last_add = Annotation.where(tree_id: tree_id, message: 'add').order('id desc').first
    last_add ? last_add.value.split(',').last.split(':').first.to_i : 0
  end

  # Rebuilds the same section from the graph tables. Each anchor row becomes an
  # NListItem with its N child; each arc row becomes its list item with an Arc
  # child and one child per label. Values are keyed by the node's own iid, since
  # the projection doesn't record annotation ids.
  def graph_tree_section
    # The long way round, kept as the sanity check: read back what a snapshot
    # stored. Rows carry graph_id, since they exist as database rows here.
    tree_section_from_graph(
      nodes: GraphNode.by_tree(tree_id).order(:iid).map { |n|
        { iid: n.iid, n_iid: n.n_iid, docid: n.docid, time: n.time, graph_id: n.id }
      },
      arcs: GraphArc.by_tree(tree_id).order(:iid).map { |a|
        { iid: a.iid, name: a.name, arc_node_iid: a.arc_node_iid, beg_iid: a.beg_iid, end_iid: a.end_iid, graph_id: a.id }
      },
      labels: GraphLabel.by_tree(tree_id).order(:arc_iid, :iid).map { |l|
        { iid: l.iid, arc_iid: l.arc_iid, name: l.name, value: l.value, graph_id: l.id }
      }
    )
  end

  # The same section built straight from the log, with nothing written down.
  # This is what the work page uses when it asks for the graph payload: no
  # snapshot needed, and no dependence on when the last one ran.
  def graph_memory_tree_section
    tree_section_from_graph(**graph_projection)
  end

  # Rows (from either source) → the payload's tree section.
  def tree_section_from_graph(nodes:, arcs:, labels:)
    anchors = nodes
    arc_rows = arcs
    label_rows = labels
    nodes = []
    values = []
    values = []
    add = ->(iid, name, parent_iid, index, level, value_id, extra = {}) do
      nodes << {
        iid: iid, name: name, parent_iid: parent_iid, index: index, level: level,
        annotation_id: value_id, user_id: user_id, task_id: task_id
      }.merge(extra)
    end

    # A list item points at the message that created its group, whose value is
    # the group string — "1:NListItem,2:N". The graph tables don't store that
    # string, but they hold everything in it, so rebuild it.
    group = ->(pairs) { pairs.map { |iid, name| "#{iid}:#{name}" }.join(",") }

    anchors.sort_by { |a| a[:iid] }.each do |anchor|
      add.call(anchor[:iid], "NListItem", nil, nil, 2, anchor[:iid], { graph_id: anchor[:graph_id] })
      add.call(anchor[:n_iid], "N", anchor[:iid], 0, 3, anchor[:n_iid], { graph_id: anchor[:graph_id] })
      values << {
        id: anchor[:iid], value: group.call([ [ anchor[:iid], "NListItem" ], [ anchor[:n_iid], "N" ] ]),
        docid: nil, beg: 0.0, end: 0.0, text: nil, source_id: nil
      }
      values << {
        id: anchor[:n_iid], value: nil, docid: anchor[:docid],
        beg: anchor[:time]&.to_f, end: 0.0, text: nil, source_id: nil
      }
    end

    by_arc = label_rows.sort_by { |l| [ l[:arc_iid], l[:iid] ] }.group_by { |l| l[:arc_iid] }
    arc_rows.sort_by { |a| a[:iid] }.each do |arc|
      arc_labels = by_arc[arc[:iid]] || []
      pairs = [ [ arc[:iid], arc[:name] ] ]
      pairs << [ arc[:arc_node_iid], "Arc" ] if arc[:arc_node_iid]
      arc_labels.each { |l| pairs << [ l[:iid], l[:name] ] }
      add.call(arc[:iid], arc[:name], nil, nil, 2, arc[:iid], { graph_id: arc[:graph_id], arc_node_iid: arc[:arc_node_iid] })
      values << {
        id: arc[:iid], value: group.call(pairs), docid: nil,
        beg: 0.0, end: 0.0, text: nil, source_id: nil
      }
      if arc[:arc_node_iid]
        add.call(arc[:arc_node_iid], "Arc", arc[:iid], 0, 3, arc[:arc_node_iid], { graph_id: arc[:graph_id], arc_node_iid: arc[:arc_node_iid] })
        values << {
          id: arc[:arc_node_iid], value: nil, docid: nil,
          beg: arc[:beg_iid], end: arc[:end_iid], text: nil, source_id: nil
        }
      end
      arc_labels.each_with_index do |label, i|
        add.call(label[:iid], label[:name], arc[:iid], i + 1, 3, label[:iid], { graph_id: label[:graph_id], arc_node_iid: arc[:arc_node_iid] })
        values << {
          id: label[:iid], value: label[:value], docid: nil,
          beg: 0.0, end: 0.0, text: nil, source_id: nil
        }
      end
    end

    {
      "nodes" => nodes,
      "node_values" => values,
      # Not the highest iid in the graph: last_iid is where the client resumes
      # handing out iids, so it has to be the high-water mark. A deleted group
      # leaves no rows behind, so the tables can't tell us — after deleting the
      # newest segment the graph's maximum is lower than the last one issued,
      # and a client trusting it would hand out iids that have been used. The
      # log knows, so take it from there.
      "last_iid" => last_add_iid
    }
  end

  # The client payload built from the stored graph rather than the log —
  # requires a snapshot, since it reads the tables. The sanity-check form.
  def graph_payload(depth = 'deep')
    to_hash(false, depth, false, nodes_from: :graph)
  end

  # The same payload, built from the log through the graph shape without
  # persisting anything. This is what the work page serves for ?graph=1: no
  # snapshot required, so it can't be stale.
  def graph_memory_payload(depth = 'deep')
    to_hash(false, depth, false, nodes_from: :graph_memory)
  end

end
