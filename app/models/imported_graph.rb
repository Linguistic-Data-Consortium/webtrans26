# An annotation graph that came from outside the tool: a reference transcript,
# an ASR pass, a forced alignment. Anchors, spans and labels — the same
# formalism the annotator side is stored in, so the two can be read and
# collated through one interface.
#
# What it doesn't carry is the expansion the annotator side needs: no iid, no
# user, no task, no annotations row behind each value. Those record who did
# what; an import has no actions in it. Its provenance is one fact about the
# whole file, and it lives here.
#
# One graph per (docid, name): a document can hold several tiers — a human
# reference and an ASR pass over the same audio — and re-importing a tier
# replaces it.
class ImportedGraph < ApplicationRecord
  has_many :imported_nodes, dependent: :delete_all
  has_many :imported_arcs, dependent: :delete_all
  has_many :imported_labels, dependent: :delete_all

  # What an imported transcript segment is called. Deliberately not the
  # annotator side's "SegmentListItem" — collating the two needs a mapping
  # either way, and it should be visible rather than implied by a shared name.
  DEFAULT_ARC_NAME = "Segment".freeze

  # The tier read when nothing says otherwise — see KitType's
  # transcribe_text_only constraint, whose value can name another.
  DEFAULT_TIER = "reference".freeze

  # Times are stored to the column's scale; anchors are shared by equality, so
  # everything that becomes a node has to be rounded the same way first.
  TIME_SCALE = 6

  # Rows per insert. Large enough that a seven thousand document import is
  # tens of statements rather than thousands, small enough that no single
  # statement carries the whole file.
  SLICE = 1000

  scope :for_docid, ->(docid) { where(docid: docid) }
  scope :for_stem, ->(value) { where(stem: Docid.stem(value)) }
  scope :named, ->(name) { where(name: name) }

  # The tier a kit should read, given how its source is spelled. A kit's
  # source_uid is a path to audio and an imported document id is whatever the
  # transcript called it, so they meet at the stem — see Docid.stem.
  def self.for_source(source_uid, tier: DEFAULT_TIER)
    return nil if source_uid.to_s.empty?
    for_stem(source_uid).named(tier).first
  end

  # Replace (docid, name) with these rows, and return the graph.
  #
  #   rows: [ { beg:, end:, name: (optional arc name), labels: { "Text" => … } } ]
  #
  # Wholesale replacement rather than a diff: the source is a file, the rows
  # are derived from it, and a partial update would leave a graph that matches
  # no version of it.
  def self.build(docid:, name:, rows:, source: nil, format: nil, content_hash: nil)
    build_all(
      name: name, documents: [ [ docid, rows ] ],
      source: source, format: format, content_hash: content_hash
    ).first
  end

  # The same for many documents at once — `documents` being [[docid, rows], …].
  #
  # Everything here is batched across the whole set rather than done per
  # document, which is the difference between importing seven thousand of them
  # in seconds and in a minute: one upsert for the graphs, one delete per
  # table, and the anchors, spans and labels inserted in slices. The per
  # document version spent nine tenths of its time in Ruby building the same
  # statements over and over — the database was never the slow part.
  #
  # Anchors are still shared within a document and never across one: they're
  # keyed by (graph, time) throughout.
  def self.build_all(name:, documents:, source: nil, format: nil, content_hash: nil)
    return [] if documents.empty?
    now = Time.zone.now
    transaction do
      graphs = upsert_graphs(documents.map(&:first), name, source, format, content_hash, now)
      id_for = graphs.index_by(&:docid).transform_values(&:id)
      clear_rows(id_for.values)

      # [graph_id, spans, times] per document, in the order given.
      per_document = documents.map do |docid, rows|
        spans = rows.filter_map { |row| span(row) }
        [ id_for[docid], spans, spans.flat_map { |s| [ s[:beg], s[:end] ] }.uniq.sort ]
      end

      write_anchors_arcs_and_labels(per_document, now)
      graphs
    end
  end

  # Raised when a file's document ids can't be turned into docids this app
  # uses — the mismatch is a decision, not something to guess at.
  class DocidError < StandardError; end

  # Read a TSV the way the tool's own importer reads it (parse_tsv.js: both
  # column layouts, optional header, rows without real times skipped) and store
  # the result under one docid. Text, Speaker and Section become labels when
  # the file has them.
  #
  # Refuses a file naming several documents rather than flattening them
  # together: they'd share anchors at any time they have in common, and every
  # query over the result would cross documents.
  def self.import_tsv(docid:, name:, text:, source: nil)
    rows = TsvReader.rows(text)
    documents = rows.filter_map { |r| r[:document] }.uniq
    if documents.size > 1
      raise DocidError, "#{source || 'that file'} names #{documents.size} documents " \
                        "(#{documents.first(3).join(', ')}…) — import it with " \
                        "import_tsv_by_document, which gives each one its own graph"
    end
    build(
      docid: docid, name: name, source: source, format: "tsv",
      content_hash: Digest::SHA256.hexdigest(text), rows: rows
    )
  end

  # The same, for a file holding several documents: one graph per document id
  # in the file, each docid produced by `resolve`. Returns the graphs.
  #
  # One transaction for the file, not one per document. Rails treats the
  # nested ones inside #build as no-ops, so a file with thousands of documents
  # commits once instead of twice per document — the difference between a
  # minute and a few seconds. It also makes the import all-or-nothing: a
  # document that can't be resolved takes the whole file with it, which is the
  # behaviour you want when the mapping turns out to be wrong halfway through.
  def self.import_tsv_by_document(name:, text:, source: nil, resolve: Docid.verbatim)
    hash = Digest::SHA256.hexdigest(text)
    by_document = TsvReader.rows(text).group_by { |r| r[:document] }
    # Every id resolved before anything is written, so a mapping that fails
    # halfway through fails before the first row lands.
    documents = by_document.map { |key, rows| [ resolve.call(key), rows ] }
    build_all(
      name: name, documents: documents,
      source: source, format: "tsv", content_hash: hash
    )
  end

  # Remove graphs and their rows, in a handful of statements rather than three
  # per graph. destroy_all leans on dependent: :delete_all, which is fine for
  # one graph and takes twenty seconds for seven thousand. Returns how many
  # went.
  def self.remove_all(scope = all)
    ids = scope.pluck(:id)
    return 0 if ids.empty?
    transaction do
      ids.each_slice(SLICE) do |slice|
        clear_rows(slice)
        where(id: slice).delete_all
      end
    end
    ids.size
  end

  # What the documents in a file would be stored as, without storing anything.
  # `resolve` may raise per key, so failures come back as the message rather
  # than stopping the walk — the point is to see the whole mapping at once.
  def self.plan_tsv(text:, resolve: Docid.verbatim)
    TsvReader.rows(text).group_by { |r| r[:document] }.map do |key, rows|
      docid = begin
        resolve.call(key)
      rescue DocidError => e
        e.message
      end
      { document: key, docid: docid, spans: rows.size }
    end
  end

  # True when this text is what's already stored — a re-import that would
  # change nothing.
  def matches?(text) = content_hash.present? && content_hash == Digest::SHA256.hexdigest(text)

  # Replace just this graph's rows, keeping its provenance as it stands.
  def replace_rows(rows)
    self.class.build(
      docid: docid, name: name, rows: rows,
      source: source, format: format, content_hash: content_hash
    )
    reload
  end

  # The graph as rows, in the shape the annotator side's projection also comes
  # back in: anchors, then spans in time order, then what each span says.
  def graph_rows
    {
      nodes: ImportedNode.by_graph(id).in_time_order.map(&:to_row),
      arcs: ImportedArc.by_graph(id).in_time_order.map(&:to_row),
      labels: ImportedLabel.by_graph(id).order(:imported_arc_id, :id).map(&:to_row)
    }
  end

  # The same graph flattened to a transcript: one row per span, its labels
  # resolved. What a query or an export reads.
  def transcript_rows(name: DEFAULT_ARC_NAME)
    arcs = ImportedArc.by_graph(id).in_time_order
    arcs = arcs.named(name) if name
    flatten(arcs)
  end

  # Spans touching a stretch of the document, flattened the same way.
  def overlapping(beg, fin, name: DEFAULT_ARC_NAME)
    arcs = ImportedArc.by_graph(id).overlapping(beg, fin).in_time_order
    arcs = arcs.named(name) if name
    flatten(arcs)
  end

  private

  # One query for the labels rather than one per arc: an import can be large.
  def flatten(arcs)
    arcs = arcs.to_a
    by_arc = ImportedLabel.for_arc(arcs.map(&:id)).group_by(&:imported_arc_id)
    arcs.map do |arc|
      values = (by_arc[arc.id] || []).each_with_object({}) { |l, h| h[l.name] = l.value }
      {
        id: arc.id, name: arc.name, beg: arc.beg&.to_f, end: arc[:end]&.to_f,
        text: values["Text"].to_s, speaker: values["Speaker"].to_s, section: values["Section"].to_s,
        labels: values
      }
    end
  end

  class << self
    private

    # A row with both times, rounded to what the column stores, or nothing —
    # an arc without two anchors isn't a span.
    def span(row)
      beg = time(row[:beg] || row["beg"])
      fin = time(row[:end] || row["end"])
      return nil if beg.nil? || fin.nil?
      labels = row[:labels] || row["labels"] || {}
      { beg: beg, end: fin, name: row[:name] || row["name"] || DEFAULT_ARC_NAME, labels: labels }
    end

    def time(value)
      return nil if value.nil? || value.to_s.strip.empty?
      BigDecimal(value.to_s).round(TIME_SCALE)
    rescue ArgumentError
      nil
    end

    # One statement for every graph in the file. Rows that already exist keep
    # their id and their created_at; a re-import only moves the provenance on.
    def upsert_graphs(docids, name, source, format, content_hash, now)
      upsert_all(
        docids.map { |docid|
          {
            docid: docid, name: name, stem: Docid.stem(docid), source: source, format: format,
            content_hash: content_hash, created_at: now, updated_at: now
          }
        },
        unique_by: %i[ docid name ],
        update_only: %i[ stem source format content_hash updated_at ]
      )
      docids.each_slice(SLICE).flat_map { |slice| where(name: name, docid: slice).to_a }
    end

    def clear_rows(graph_ids)
      ImportedLabel.where(imported_graph_id: graph_ids).delete_all
      ImportedArc.where(imported_graph_id: graph_ids).delete_all
      ImportedNode.where(imported_graph_id: graph_ids).delete_all
    end

    # Anchors, then the spans that point at them, then what those spans say —
    # each in as few statements as the slice size allows, and each level
    # keeping the order it was built in so the next one can name its ids.
    def write_anchors_arcs_and_labels(per_document, now)
      node_rows = per_document.flat_map { |graph_id, _spans, times|
        times.map { |t| { imported_graph_id: graph_id, time: t, created_at: now, updated_at: now } }
      }
      node_ids = insert_returning_ids(ImportedNode, node_rows)

      # (graph, time) -> node id. Keyed by the graph too, so two documents that
      # both start at 0.0 keep their own anchors.
      anchor = {}
      i = 0
      per_document.each do |graph_id, _spans, times|
        times.each { |t| anchor[[ graph_id, t ]] = node_ids[i]; i += 1 }
      end

      arc_rows = per_document.flat_map { |graph_id, spans, _times|
        spans.map { |s|
          {
            imported_graph_id: graph_id, name: s[:name],
            beg_node_id: anchor[[ graph_id, s[:beg] ]], end_node_id: anchor[[ graph_id, s[:end] ]],
            beg: s[:beg], end: s[:end], created_at: now, updated_at: now
          }
        }
      }
      arc_ids = insert_returning_ids(ImportedArc, arc_rows)

      label_rows = []
      i = 0
      per_document.each do |graph_id, spans, _times|
        spans.each do |s|
          arc_id = arc_ids[i]
          i += 1
          s[:labels].each do |label_name, value|
            next if value.nil? || value.to_s.empty?
            label_rows << {
              imported_arc_id: arc_id, imported_graph_id: graph_id,
              name: label_name.to_s, value: value.to_s, created_at: now, updated_at: now
            }
          end
        end
      end
      insert_in_slices(ImportedLabel, label_rows)
    end

    # Sliced so one statement never carries a whole large import, and the ids
    # come back in insertion order rather than being read back afterwards.
    def insert_returning_ids(model, rows)
      rows.each_slice(SLICE).flat_map { |slice|
        model.insert_all(slice, returning: %w[ id ]).rows.flatten
      }
    end

    def insert_in_slices(model, rows)
      rows.each_slice(SLICE).each { |slice| model.insert_all(slice) }
    end
  end

  # Turning a document id written in a file into a docid this app uses.
  #
  # Deliberately a choice per import rather than a rule: a transcript may name
  # its document as a bare id, a file name or a path, and whether the matching
  # docid carries a directory or a .wav can't be read off either one.
  module Docid
    # What two spellings of the same document have in common: no channel
    # suffix, no directory, no extension, case-insensitive.
    #
    # The channel suffix is a trailing ':A'..':D' — the waveform appends one
    # per channel of a stereo kit. Matched narrowly on purpose: a kit source
    # is often a URL, and taking everything before the first colon turns
    # "s3://bucket/rec.wav" into "s3".
    CHANNEL_SUFFIX = /:[A-D]\z/

    def self.stem(value)
      base = File.basename(value.to_s.sub(CHANNEL_SUFFIX, ""))
      base.sub(/\.[^.]+\z/, "").downcase
    end

    # The file's own ids, used as they are.
    def self.verbatim = ->(key) { key }

    # A format for building a docid out of each id: "/audio/%s.wav".
    def self.template(format)
      ->(key) { format.include?("%s") ? format % key : "#{format}#{key}" }
    end

    # Match each id against docids already known here — kit sources, say —
    # by stem, so a missing or extra .wav doesn't matter. Refuses to guess when
    # a stem names more than one candidate.
    def self.match(candidates)
      index = {}
      candidates.compact.uniq.each { |c| (index[stem(c)] ||= []) << c }
      lambda do |key|
        found = index[stem(key)] || []
        raise DocidError, "'#{key}' matches #{found.size} known documents (#{found.join(', ')})" if found.size > 1
        raise DocidError, "'#{key}' matches no known document" if found.empty?
        found.first
      end
    end

    # The docids the annotator side already works with.
    def self.kit_sources = Kit.distinct.pluck(:source_uid).compact.reject(&:empty?)
  end

  # Reads the TSV layouts parse_tsv.js reads, so an import doesn't depend on a
  # browser having done it. Kept deliberately close to that file: two column
  # layouts, an optional header naming the columns, and rows without real times
  # skipped.
  #
  # One thing it reads that parse_tsv.js doesn't: which column names the
  # document. The client never needed it — it imports a transcript for the kit
  # already open — but a file handed to the server routinely holds several.
  module TsvReader
    HEADER_FIELDS = {
      "file" => :document, "source" => :document, "audio" => :document,
      "beg" => :beg, "begin" => :beg,
      "end" => :end,
      "text" => :text,
      "speaker" => :speaker,
      "section" => :section
    }.freeze
    # "Kit" style leads with a kit id and the document; "file" style with the
    # document alone. ("Audio" is what this app's own download calls that
    # column; "Source" is what older files call it.)
    KIT_COLUMNS  = { document: 1, beg: 2, end: 3, text: 4, speaker: 5, section: 6 }.freeze
    FILE_COLUMNS = { document: 0, beg: 1, end: 2, text: 3, speaker: 4, section: 5 }.freeze

    def self.rows(text)
      columns = nil
      rows = []
      text.to_s.split("\n").each do |line|
        cells = line.sub(/\r\z/, "").split("\t")
        if columns.nil?
          header = header_columns(cells)
          columns = header || infer_columns(cells)
          next if header # a named header isn't data; a headerless first line is
        end
        next if cells.size <= 1
        next unless time?(cells[columns[:beg]]) && time?(cells[columns[:end]])
        rows << row(cells, columns)
      end
      rows.sort_by { |r| r[:beg] }
    end

    # A first line is a header if it starts with Kit or file *and* names at
    # least the times and the text — so a "file" style data row whose file name
    # begins with "file" isn't eaten as one.
    def self.header_columns(cells)
      return nil unless /\A(kit|file)/i.match?(cells[0].to_s)
      columns = {}
      cells.each_with_index do |cell, i|
        field = HEADER_FIELDS[cell.to_s.strip.downcase]
        columns[field] = i if field && !columns.key?(field)
      end
      ( %i[ beg end text ] - columns.keys ).empty? ? columns : nil
    end

    # No header: tell the layouts apart by where the times are.
    def self.infer_columns(cells)
      return KIT_COLUMNS  if time?(cells[2]) && time?(cells[3])
      return FILE_COLUMNS if time?(cells[1]) && time?(cells[2])
      KIT_COLUMNS
    end

    def self.time?(cell)
      return false if cell.nil? || cell.to_s.strip.empty?
      Float(cell.to_s, exception: false) ? true : false
    end

    def self.row(cells, columns)
      {
        # Which document the row belongs to, as the file spells it. nil when
        # the layout has no such column — then the whole file is one document.
        document: columns[:document] && cells[columns[:document]],
        beg: round3(cells[columns[:beg]]),
        end: round3(cells[columns[:end]]),
        labels: {
          # Optional columns: absent from the header, or short on this row —
          # empty either way, and empty labels aren't stored at all.
          "Text" => cells[columns[:text]].to_s,
          "Speaker" => (columns[:speaker] && cells[columns[:speaker]]).to_s,
          "Section" => (columns[:section] && cells[columns[:section]]).to_s
        }
      }
    end

    def self.round3(cell) = (Float(cell.to_s) * 1000).round / 1000.0
  end
end
