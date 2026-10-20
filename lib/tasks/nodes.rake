# The node graph is replayed from the annotation log (NodeDerivation); there is
# no nodes table any more. What is left here is the sizing question that replay
# raises: how much log does a tree carry?
#
#   bin/rails nodes:cost
namespace :nodes do
  desc "How much annotation log a replay has to walk"
  task cost: :environment do
    per_tree = Annotation.where.not(tree_id: nil).group(:tree_id).count
    average = per_tree.empty? ? 0 : (per_tree.values.sum.to_f / per_tree.size).round(1)

    puts "trees:            #{per_tree.size}"
    puts "annotations:      #{Annotation.count} (max #{per_tree.values.max.to_i}/tree, avg #{average})"
    puts "messages:         #{Annotation.group(:message).count.inspect}"
    # Replay cost tracks edit history, not transcript length: this is the worst
    # case for a single node.
    changes = Annotation.where(message: "change").group(:tree_id, :iid).count
    puts "changes per node: max #{changes.values.max.to_i}"

    derived = NodeDerivation.for_trees(per_tree.keys)
    puts "derived nodes:    #{derived.values.sum { |d| d.nodes.size }}"
    anomalies = derived.sum { |tree_id, d| d.anomalies.size }
    puts "replay anomalies: #{anomalies}"
    derived.each do |tree_id, d|
      d.anomalies.each { |a| puts "  tree #{tree_id}: #{a}" }
    end
  end
end
