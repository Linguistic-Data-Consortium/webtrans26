# Importing and inspecting annotation graphs that came from outside the tool —
# reference transcripts, ASR passes, alignments:
#
#   bin/rails imported:tsv DOCID=/test_tone_10s.wav NAME=reference FILE=public/test_tone_10s.tsv
#   bin/rails imported:list DOCID=/test_tone_10s.wav
#   bin/rails imported:show DOCID=/test_tone_10s.wav NAME=reference
#   bin/rails imported:overlapping DOCID=/test_tone_10s.wav NAME=reference BEG=2 END=5
namespace :imported do
  def graph_for(name: ENV["NAME"])
    docid = ENV["DOCID"] or abort "DOCID= is required"
    abort "NAME= is required" if name.to_s.empty?
    ImportedGraph.for_docid(docid).named(name).first ||
      abort("no '#{name}' graph for #{docid} — import one first")
  end

  def print_rows(rows)
    rows.each do |r|
      extra = r[:labels].except("Text").reject { |_, v| v.to_s.empty? }
      puts "  %8.3f–%8.3f  %s%s" % [
        r[:beg], r[:end], r[:text],
        extra.any? ? "   (#{extra.map { |k, v| "#{k}=#{v}" }.join(', ')})" : ""
      ]
    end
  end

  # How the document ids in a file become docids here. A file may name its
  # documents as bare ids while this app knows them as paths, or the other way
  # round, so the mapping is stated per import rather than inferred.
  #
  #   DOCID=…      the whole file is that one document
  #   TEMPLATE=…   build one from each id: TEMPLATE=/audio/%s.wav
  #   MATCH=kits   match against kit sources by stem — no directory, no
  #                extension, no channel suffix, case-insensitive
  #   (none)       use the file's ids as they stand
  def resolver
    return ImportedGraph::Docid.template(ENV["TEMPLATE"]) if ENV["TEMPLATE"]
    return ImportedGraph::Docid.match(ImportedGraph::Docid.kit_sources) if ENV["MATCH"] == "kits"
    abort "MATCH=#{ENV['MATCH']} isn't a thing — try MATCH=kits" if ENV["MATCH"]
    ImportedGraph::Docid.verbatim
  end

  def read_file
    file = ENV["FILE"] or abort "FILE= is required"
    abort "no such file: #{file}" unless File.exist?(file)
    [ file, File.read(file) ]
  end

  def report(graph)
    puts "#{graph.docid} '#{graph.name}': #{ImportedArc.by_graph(graph.id).count} spans over " \
         "#{ImportedNode.by_graph(graph.id).count} anchors, " \
         "#{ImportedLabel.by_graph(graph.id).count} labels"
  end

  # Counted in three queries rather than three per document — a bulk import
  # runs to thousands, and printing a line each says less than the totals do.
  def report_all(graphs)
    ids = graphs.map(&:id)
    puts "#{graphs.size} documents: #{ImportedArc.where(imported_graph_id: ids).count} spans over " \
         "#{ImportedNode.where(imported_graph_id: ids).count} anchors, " \
         "#{ImportedLabel.where(imported_graph_id: ids).count} labels"
  end

  desc "Import a TSV (FILE=, NAME=; DOCID= | TEMPLATE= | MATCH=kits)"
  task tsv: :environment do
    name = ENV["NAME"] or abort "NAME= is required (reference, asr, alignment, …)"
    file, text = read_file

    if (docid = ENV["DOCID"])
      existing = ImportedGraph.for_docid(docid).named(name).first
      if existing&.matches?(text)
        puts "#{docid} '#{name}' already holds these bytes — nothing to do"
        next
      end
      begin
        report ImportedGraph.import_tsv(docid: docid, name: name, text: text, source: file)
      rescue ImportedGraph::DocidError => e
        abort "#{e.message}\n(run imported:plan to see the mapping first)"
      end
      next
    end

    begin
      graphs = ImportedGraph.import_tsv_by_document(name: name, text: text, source: file, resolve: resolver)
    rescue ImportedGraph::DocidError => e
      abort "#{e.message}\n(run imported:plan to see the whole mapping, or pass TEMPLATE=/DOCID=)"
    end
    if graphs.size <= 20
      graphs.each { |g| report g }
    else
      report_all(graphs)
    end
  end

  desc "Show what a TSV would be stored as, without storing it (FILE=; TEMPLATE= | MATCH=kits)"
  task plan: :environment do
    _file, text = read_file
    plan = ImportedGraph.plan_tsv(text: text, resolve: resolver)
    plan.each do |row|
      puts "  %-48s %5d spans  ->  %s" % [ row[:document], row[:spans], row[:docid] ]
    end
    unresolved = plan.count { |row| row[:docid].to_s.start_with?("'") }
    puts "#{plan.size} documents#{unresolved.zero? ? '' : ", #{unresolved} unresolved"}"
  end

  desc "List the tiers imported for a document (DOCID=, or all)"
  task list: :environment do
    scope = ENV["DOCID"] ? ImportedGraph.for_docid(ENV["DOCID"]) : ImportedGraph.all
    abort "nothing imported yet" if scope.none?
    scope.order(:docid, :name).each do |g|
      puts "#{g.docid}  #{g.name.ljust(12)} #{ImportedArc.by_graph(g.id).count} spans  " \
           "#{g.format} #{g.source}  imported #{g.updated_at}"
    end
  end

  desc "Print a tier as a transcript (DOCID=, NAME=)"
  task show: :environment do
    graph = graph_for
    rows = graph.transcript_rows
    puts "#{graph.docid} '#{graph.name}' — #{rows.size} spans, from #{graph.source || 'unrecorded'}"
    print_rows(rows)
  end

  desc "Print the spans touching a stretch of a document (DOCID=, NAME=, BEG=, END=)"
  task overlapping: :environment do
    graph = graph_for
    beg = Float(ENV["BEG"] || abort("BEG= is required"))
    fin = Float(ENV["END"] || abort("END= is required"))
    rows = graph.overlapping(beg, fin)
    puts "#{graph.docid} '#{graph.name}' — #{rows.size} spans touching #{beg}–#{fin}"
    print_rows(rows)
  end

  desc "Remove imported graphs and their rows (DOCID= and/or NAME= and/or SOURCE=, or ALL=true)"
  task clear: :environment do
    scope = ImportedGraph.all
    scope = scope.for_docid(ENV["DOCID"]) if ENV["DOCID"]
    scope = scope.named(ENV["NAME"]) if ENV["NAME"]
    scope = scope.where(source: ENV["SOURCE"]) if ENV["SOURCE"]

    if scope == ImportedGraph.all && ENV["ALL"] != "true"
      abort "nothing selected — pass DOCID=, NAME= or SOURCE= (or ALL=true to clear the lot)"
    end
    abort "nothing matches" if scope.none?

    if scope.count <= 20
      scope.order(:docid, :name).each { |g| puts "removing #{g.docid} '#{g.name}' (#{ImportedArc.by_graph(g.id).count} spans)" }
    end
    puts "#{ImportedGraph.remove_all(scope)} graphs removed"
  end

  desc "Print a tier as graph rows: anchors, spans, labels (DOCID=, NAME=)"
  task graph: :environment do
    puts JSON.pretty_generate(graph_for.graph_rows)
  end
end
