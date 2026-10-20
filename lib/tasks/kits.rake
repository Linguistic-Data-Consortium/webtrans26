# Inspecting what the annotation tool is actually served for a kit, without
# fighting shell quoting through kamal:
#
#   bin/rails kits:payload KIT_UID=6a7f28bc0000000000000001
#   kamal app exec -q --reuse 'bin/rails kits:payload KIT_UID=6a7f28bc…' > payload.json
#
# KIT_ID works too, for when you have the row id rather than the uid.
namespace :kits do
  # Three routes to the same tree, the way ?payload= serves them:
  #
  #   memory  (default) built through the graph shape in memory — what the
  #                     browser receives, and what needs no snapshot
  #   log               the older shape, straight off the annotation log
  #   stored            read back out of graph_nodes / graph_arcs / graph_labels,
  #                     so it shows what the last snapshot wrote
  def payload_for(kit)
    case ENV["PAYLOAD"]
    when "log" then kit.to_hash(false, "deep")
    when "stored"
      abort "no graph stored for kit ##{kit.id} — run kits:graph first" if GraphNode.by_tree(kit.tree_id).none?
      kit.graph_payload
    else kit.graph_memory_payload
    end
  end

  desc "Print the JSON the client gets when opening a kit (KIT_UID= or KIT_ID=, PAYLOAD=memory|log|stored)"
  task payload: :environment do
    kit = find_kit
    payload = payload_for(kit)
    # KitsController#get adds these after to_hash; included so what's printed is
    # what the browser receives.
    payload["other_task_user_id"] = nil
    payload["task_meta"] = kit.task&.meta
    puts JSON.pretty_generate(payload)
  end

  desc "Summarise that payload instead of printing it (KIT_UID= or KIT_ID=)"
  task payload_summary: :environment do
    kit = find_kit
    payload = payload_for(kit)
    nodes = payload["nodes"] || []

    puts "kit ##{kit.id} uid=#{kit.uid} state=#{kit.state} tree=#{kit.tree_id.inspect}"
    puts "payload:      #{payload["payload_source"]}"
    puts "annotations:  #{Annotation.where(tree_id: kit.tree_id).count}"
    puts "nodes:        #{nodes.size} (#{nodes.group_by { |n| n[:name] }.transform_values(&:size).sort.to_h.inspect})"
    puts "node_values:  #{(payload["node_values"] || []).size}"
    puts "last_iid:     #{payload["last_iid"].inspect}"
    puts "bytes:        #{payload.to_json.bytesize}"

    anomalies = kit.tree_id ? NodeDerivation.for_tree(kit.tree_id).anomalies : []
    puts "replay anomalies: #{anomalies.size}"
    anomalies.each { |a| puts "  ! #{a}" }
  end

  desc "Print the annotation graph the waveform's Graph panel receives (KIT_UID= or KIT_ID=)"
  task graph: :environment do
    kit = find_kit
    # Same call the panel makes (POST /kits/graph): rebuild from the log, then
    # return the rows. REBUILD=false reads what's already stored instead.
    graph = ENV["REBUILD"] == "false" ? kit.graph_rows : kit.graph_snapshot
    puts JSON.pretty_generate(graph)
  end

  desc "Summarise that graph instead of printing it (KIT_UID= or KIT_ID=)"
  task graph_summary: :environment do
    kit = find_kit
    graph = ENV["REBUILD"] == "false" ? kit.graph_rows : kit.graph_snapshot

    puts "kit ##{kit.id} uid=#{kit.uid} tree=#{kit.tree_id}"
    puts "annotations:  #{Annotation.where(tree_id: kit.tree_id).count}"
    puts "graph_nodes:  #{graph[:nodes].size}"
    puts "graph_arcs:   #{graph[:arcs].size} (#{graph[:arcs].group_by { |a| a[:name] }.transform_values(&:size).sort.to_h.inspect})"
    puts "graph_labels: #{graph[:labels].size} (#{graph[:labels].group_by { |l| l[:name] }.transform_values(&:size).sort.to_h.inspect})"
    puts "bytes:        #{graph.to_json.bytesize}"

    # An arc pointing at an anchor that isn't there, or a label on no arc, means
    # the projection and the log disagree.
    anchors = graph[:nodes].map { |n| n[:iid] }
    arcs = graph[:arcs].map { |a| a[:iid] }
    # Only a group with an Arc child is claiming to span two anchors, so only
    # those can dangle. A group without one — groups.js is free to declare them,
    # and ugain's ItemList and ThingList are exactly this shape — has no
    # endpoints to be missing, and reporting it as broken buried the real signal:
    # a 64-item reading-theater tree read as "arcs missing an anchor: 64".
    spanning, unspanned = graph[:arcs].partition { |a| a[:arc_node_iid] }
    dangling = spanning.reject { |a| anchors.include?(a[:beg_iid]) && anchors.include?(a[:end_iid]) }
    orphans = graph[:labels].reject { |l| arcs.include?(l[:arc_iid]) }
    puts "arcs missing an anchor: #{dangling.size}"
    dangling.first(5).each { |a| puts "  ! arc #{a[:iid]} #{a[:beg_iid]}->#{a[:end_iid]}" }
    unless unspanned.empty?
      by_name = unspanned.group_by { |a| a[:name] }.transform_values(&:size).sort.to_h
      puts "groups with no span:    #{unspanned.size} #{by_name.inspect} (not an error)"
    end
    puts "labels with no arc:     #{orphans.size}"
    orphans.first(5).each { |l| puts "  ! label #{l[:iid]} on arc #{l[:arc_iid]}" }
  end

  # The sanity check the two payloads exist for: same tree, two independent
  # routes to the same description of it.
  desc "Compare the log payload with the graph one (KIT_UID= or KIT_ID=)"
  task payload_diff: :environment do
    kit = find_kit
    if ENV["STORED"] == "true" && GraphNode.by_tree(kit.tree_id).none?
      abort "no graph stored for kit ##{kit.id} — run kits:graph first"
    end

    log = kit.to_hash(false, "deep")
    graph = ENV["STORED"] == "true" ? kit.graph_payload : kit.graph_memory_payload
    fields = ->(n) { [ n[:iid], n[:name], n[:parent_iid], n[:level] ] }
    log_nodes = log["nodes"].map(&fields).sort_by { |f| f.first.to_i }
    graph_nodes = graph["nodes"].map(&fields).sort_by { |f| f.first.to_i }

    puts "kit ##{kit.id} uid=#{kit.uid} tree=#{kit.tree_id}"
    puts "keys:      #{log.keys.sort == graph.keys.sort ? "same" : "DIFFER: #{(log.keys | graph.keys) - (log.keys & graph.keys)}"}"
    puts "last_iid:  log=#{log["last_iid"].inspect} graph=#{graph["last_iid"].inspect}#{log["last_iid"] == graph["last_iid"] ? "" : "  DIFFER"}"
    puts "nodes:     log=#{log_nodes.size} graph=#{graph_nodes.size}"

    (log_nodes - graph_nodes).first(10).each { |n| puts "  only in log:   iid=#{n[0]} #{n[1]} parent=#{n[2].inspect} level=#{n[3]}" }
    (graph_nodes - log_nodes).first(10).each { |n| puts "  only in graph: iid=#{n[0]} #{n[1]} parent=#{n[2].inspect} level=#{n[3]}" }

    # Values are keyed differently — the log by annotation id, the graph by the
    # node's own iid — so compare what each node ends up pointing at.
    value_for = ->(payload) do
      by_id = payload["node_values"].index_by { |v| v[:id] }
      payload["nodes"].each_with_object({}) do |n, h|
        v = by_id[n[:annotation_id]]
        h[n[:iid]] = v && [ v[:value], v[:docid], v[:beg], v[:end] ]
      end
    end
    lv = value_for.call(log)
    gv = value_for.call(graph)
    mismatched = (lv.keys & gv.keys).reject { |iid| lv[iid] == gv[iid] }
    puts "values:    #{mismatched.empty? ? "match on every shared node" : "#{mismatched.size} node(s) differ"}"
    mismatched.first(10).each { |iid| puts "  iid #{iid}: log=#{lv[iid].inspect} graph=#{gv[iid].inspect}" }

    abort "the payloads disagree" if log_nodes != graph_nodes || mismatched.any?
    puts "the graph payload describes the same tree as the log payload"
  end

  def find_kit
    uid = ENV["KIT_UID"]
    id = ENV["KIT_ID"]
    abort "set KIT_UID=<kit uid> or KIT_ID=<kit id>" if uid.nil? && id.nil?
    kit = uid ? Kit.find_by(uid: uid) : Kit.find_by(id: id)
    abort "no kit with #{uid ? "uid #{uid}" : "id #{id}"}" if kit.nil?
    abort "kit ##{kit.id} has no tree — it has never been opened" if kit.tree_id.nil?
    kit
  end
end
