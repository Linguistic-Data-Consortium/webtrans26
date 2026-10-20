# Copying one task from one database into another — in practice, a production
# task into development, so it can be opened, read and debugged locally.
# `bin/rails task:pull` is the command; this is what it does.
#
# What it carries is what the task *is*: the project and workflow it belongs to,
# its kit type and the node class and class def behind that, its members, its
# kits, their trees, and every annotation on them. The annotations are the
# record — everything the tool draws is replayed from them (ARCHITECTURE.md,
# "The record") — so a copy that has them has the task.
#
# What it leaves behind, deliberately:
#
#   graph_nodes / graph_arcs / graph_labels   projections, rebuilt on demand
#   segments / sections                       likewise, by Kit#snapshot
#   actions, kit_stats, kit_values,           operational history; none of it
#   kit_states, versions, sessions            is read to render a transcript
#
# Rows are copied as raw column values rather than through the models. Several
# of these columns are Ruby-serialized hashes (Task#meta, KitType#constraints,
# Kit#source) that a model round trip would re-encode; validations and callbacks
# would fire too, and a re-import would trip over Task's uniqueness check on
# name. Raw out, raw in, and the copy is exact.
class TaskTransfer
  FORMAT = 1

  class Refused < StandardError; end

  # In insertion order: a table's referents come before it. There are no foreign
  # keys declared in this schema, but it is the order someone reading a dump
  # will expect, and it keeps the failure obvious if one is ever added.
  TABLES = %w[
    projects workflows class_defs node_classes kit_types users
    tasks task_users task_docids kit_batches sources trees kits annotations
  ].freeze

  # Rows a task shares with the rest of the database — its project, the workflow
  # and kit type it uses, the class def and node classes behind that, and the
  # people on it. These are matched on a natural key rather than carried over by
  # id: this database has its own project 7, and it may well not be the same
  # project. Whatever is found here is kept and used; only what's missing is
  # created.
  MERGED = {
    "projects" => { key: "name" },
    "workflows" => { key: "name" },
    "class_defs" => { key: "name" },
    "node_classes" => { key: "name" },
    "kit_types" => { key: "name" },
    "users" => { key: "email_address", scrub: true }
  }.freeze

  # Every column pointing at one of those, so the rows arriving here point at
  # the local row rather than at whatever happens to live at that id.
  REFERENCES = {
    "node_classes" => { "class_def_id" => "class_defs", "parent_id" => "node_classes" },
    "kit_types" => { "node_class_id" => "node_classes" },
    "tasks" => { "project_id" => "projects", "workflow_id" => "workflows",
                 "kit_type_id" => "kit_types", "lock_user_id" => "users" },
    "task_users" => { "user_id" => "users" },
    "kit_batches" => { "user_id" => "users", "created_by" => "users" },
    "sources" => { "user_id" => "users" },
    "trees" => { "class_def_id" => "class_defs", "user_id" => "users" },
    "kits" => { "kit_type_id" => "kit_types", "user_id" => "users", "not_user_id" => "users" },
    "annotations" => { "user_id" => "users" }
  }.freeze

  # What the task itself is made of. These keep their production ids, so a kit
  # id in a bug report or a URL means the same thing in both places.
  OWNED = (TABLES - MERGED.keys).freeze

  # Annotations are the bulk of any real task; one statement per row is what
  # makes an import take a minute rather than a second. Same lesson as
  # ImportedGraph's writer.
  SLICE = 500

  class << self
    # ── out ────────────────────────────────────────────────────────────────

    def export(task_id)
      task = rows("SELECT * FROM tasks WHERE id = ?", task_id).first
      raise Refused, "no task ##{task_id} in #{Rails.env}" if task.nil?

      collected = collect(task_id, task)
      {
        "format" => FORMAT,
        "exported_at" => Time.current.iso8601,
        "exported_from" => Rails.env,
        "schema_version" => schema_version,
        "task_id" => task_id,
        "task_name" => task["name"],
        # Columns once, then a row as an array of values: a busy task is
        # hundreds of thousands of annotations, and repeating the column names
        # on each of them would be most of the file.
        "tables" => TABLES.index_with do |name|
          columns = db.columns(name).map(&:name)
          { "columns" => columns, "rows" => (collected[name] || []).map { |r| columns.map { |c| r[c] } } }
        end
      }
    end

    def summarise(dump)
      TABLES.map { |t| "#{dump['tables'][t]['rows'].length} #{t}" }.join(", ")
    end

    # ── in ─────────────────────────────────────────────────────────────────

    # Returns a count per table. `replace` overwrites a task of the same id that
    # is already here; without it, finding one is a refusal.
    def import(dump, replace: false)
      # This writes one database's task into another. Production is never the
      # right end of that, and it is not a mistake worth leaving room for.
      raise Refused, "refusing to import into #{Rails.env}" if Rails.env.production?
      raise Refused, "unknown dump format #{dump['format'].inspect}" unless dump["format"] == FORMAT

      check_columns(dump)
      task_id = dump["task_id"]
      existing = Task.find_by(id: task_id)
      raise Refused, already_here(task_id, existing) if existing && !replace

      counts = {}
      ActiveRecord::Base.transaction do
        remove(task_id) if existing

        # The shared rows first, each giving a map from the id in the dump to
        # the id here. Then the task's own rows, pointed through those maps.
        maps = {}
        MERGED.each do |name, config|
          maps[name] = merge_table(dump, name, config, maps)
          counts[name] = maps[name].length
        end
        fix_self_references(maps)

        OWNED.each do |name|
          rows = resolve(table(dump, name), name, maps)
          next if rows.empty?
          insert_rows(name, rows)
          counts[name] = rows.length
        end
      end
      counts
    end

    # Everything this task's own dump would have put here, and nothing else.
    # Projects, workflows, kit types, class defs and users are deliberately left
    # alone: they are shared, and another task may be sitting on them.
    def remove(task_id)
      kits = Kit.where(task_id: task_id)
      tree_ids = kits.pluck(:tree_id).compact.uniq

      Annotation.where(task_id: task_id).delete_all
      if tree_ids.any?
        Annotation.where(tree_id: tree_ids).delete_all
        GraphNode.where(tree_id: tree_ids).delete_all
        GraphArc.where(tree_id: tree_ids).delete_all
        GraphLabel.where(tree_id: tree_ids).delete_all
        Segment.where(tree_id: tree_ids).delete_all
        Section.where(tree_id: tree_ids).delete_all
      end
      kits.delete_all
      Tree.where(id: tree_ids).delete_all if tree_ids.any?
      TaskUser.where(task_id: task_id).delete_all
      TaskDocid.where(task_id: task_id).delete_all
      KitBatch.where(task_id: task_id).delete_all
      Source.where(task_id: task_id).delete_all
      Task.where(id: task_id).delete_all
    end

    private

    def db = ActiveRecord::Base.connection

    # Which migration this database is at, so a dump says what shape it was
    # taken in and the load can say when that differs.
    def schema_version = db.pool.migration_context.current_version.to_s

    def rows(sql, *binds)
      db.select_all(ActiveRecord::Base.sanitize_sql_array([ sql, *binds ])).to_a
    end

    def ids_from(rows, *columns)
      rows.flat_map { |r| columns.map { |c| r[c] } }.compact.uniq
    end

    # `IN (?)` on an empty array is a syntax error, so every list that might be
    # empty gets a value that matches nothing instead.
    def none = [ -1 ]

    def collect(task_id, task)
      kits = rows("SELECT * FROM kits WHERE task_id = ?", task_id)
      tree_ids = ids_from(kits, "tree_id")
      trees = tree_ids.empty? ? [] : rows("SELECT * FROM trees WHERE id IN (?)", tree_ids)

      # By task as well as by tree: a kit whose tree was replaced still has its
      # earlier annotations on the task, and the log is the thing worth having.
      annotations = rows(
        "SELECT * FROM annotations WHERE task_id = ? OR tree_id IN (?)",
        task_id, tree_ids.presence || none
      )

      batch_ids = (ids_from(kits, "kit_batch_id") +
                   ids_from(rows("SELECT id FROM kit_batches WHERE task_id = ?", task_id), "id")).uniq
      kit_type_ids = (ids_from(kits, "kit_type_id") + [ task["kit_type_id"] ]).compact.uniq
      node_classes = node_class_chain(ids_from(
        kit_type_ids.empty? ? [] : rows("SELECT * FROM kit_types WHERE id IN (?)", kit_type_ids),
        "node_class_id"
      ))
      class_def_ids = (ids_from(node_classes, "class_def_id") + ids_from(trees, "class_def_id")).uniq

      collected = {
        "projects" => rows("SELECT * FROM projects WHERE id = ?", task["project_id"]),
        "workflows" => (task["workflow_id"] ? rows("SELECT * FROM workflows WHERE id = ?", task["workflow_id"]) : []),
        "class_defs" => (class_def_ids.empty? ? [] : rows("SELECT * FROM class_defs WHERE id IN (?)", class_def_ids)),
        "node_classes" => node_classes,
        "kit_types" => (kit_type_ids.empty? ? [] : rows("SELECT * FROM kit_types WHERE id IN (?)", kit_type_ids)),
        "tasks" => [ task ],
        "task_users" => rows("SELECT * FROM task_users WHERE task_id = ?", task_id),
        "task_docids" => rows("SELECT * FROM task_docids WHERE task_id = ?", task_id),
        "kit_batches" => (batch_ids.empty? ? [] : rows("SELECT * FROM kit_batches WHERE id IN (?)", batch_ids)),
        "sources" => sources_for(task_id),
        "trees" => trees,
        "kits" => kits,
        "annotations" => annotations
      }

      # Everyone any of these rows names — read off the same reference table the
      # import points through, so the two can't drift apart.
      user_ids = REFERENCES.flat_map do |table, refs|
        columns = refs.select { |_, target| target == "users" }.keys
        columns.empty? ? [] : ids_from(collected[table] || [], *columns)
      end.uniq
      collected["users"] = user_ids.empty? ? [] : rows("SELECT * FROM users WHERE id IN (?)", user_ids)
      collected
    end

    # The node class a kit type points at, and its parents — what ClassDef
    # resolution walks up.
    def node_class_chain(start)
      found = []
      pending = start
      while pending.any?
        batch = rows("SELECT * FROM node_classes WHERE id IN (?)", pending)
        found.concat(batch)
        pending = ids_from(batch, "parent_id") - found.map { |r| r["id"] }
      end
      found
    end

    # A kit names its source through a serialized hash, so the model is the only
    # thing that can read it. Read-only, and only to decide which rows to carry.
    def sources_for(task_id)
      kits = Kit.where(task_id: task_id)
      uids = kits.filter_map { |k| k.source.is_a?(Hash) ? k.source[:uid] : nil }.uniq
      ids = kits.filter_map { |k| k.source.is_a?(Hash) ? k.source[:id] : nil }.grep(Integer).uniq
      rows(
        "SELECT * FROM sources WHERE task_id = ? OR uid IN (?) OR id IN (?)",
        task_id, uids.presence || [ "" ], ids.presence || none
      )
    end

    # Written as SQL rather than through the models, for the same reason the
    # rows were read as SQL: a serialized column (Task#meta, KitType#constraints,
    # Kit#source) holds an encoded string, and `insert_all` would put it through
    # the model's attribute types and encode it a second time. These values are
    # already in the shape the column stores.
    def insert_rows(table, rows)
      return if rows.empty?

      columns = rows.first.keys
      into = "#{db.quote_table_name(table)} (#{columns.map { |c| db.quote_column_name(c) }.join(', ')})"
      rows.each_slice(SLICE) do |slice|
        values = slice.map { |row| "(#{columns.map { |c| db.quote(row[c]) }.join(', ')})" }
        db.execute("INSERT INTO #{into} VALUES #{values.join(', ')}")
      end
    end

    def table(dump, name)
      columns = dump["tables"][name]["columns"]
      dump["tables"][name]["rows"].map { |row| columns.zip(row).to_h }
    end

    # A column the dump has and this database doesn't can't be loaded, and
    # guessing is worse than stopping. The other way round is fine — a column
    # added since the dump takes its default.
    def check_columns(dump)
      behind = TABLES.reject { |name| db.table_exists?(name) }
      if behind.any?
        raise Refused, "this database has no #{behind.join(', ')} — it is behind the dump's " \
                       "schema (#{dump['schema_version']}); run bin/rails db:migrate"
      end

      TABLES.each do |name|
        missing = dump["tables"][name]["columns"] - db.columns(name).map(&:name)
        next if missing.empty?
        raise Refused, "#{name} in the dump has columns this database doesn't: #{missing.join(', ')} " \
                       "(dump schema #{dump['schema_version']}, this database #{schema_version})"
      end
    end

    def already_here(task_id, task)
      "task #{task_id} is already in #{Rails.env} " \
      "(project #{task.project_id}, #{Kit.where(task_id: task_id).count} kits, " \
      "#{Annotation.where(task_id: task_id).count} annotations)"
    end

    # One shared table: match each row here by its natural key, create what is
    # missing, and return dump id → local id.
    def merge_table(dump, name, config, maps)
      key = config[:key]
      inserted = []

      map = table(dump, name).each_with_object({}) do |row, acc|
        value = row[key]
        local = value.presence && rows(
          "SELECT id FROM #{db.quote_table_name(name)} WHERE #{db.quote_column_name(key)} = ?", value
        ).first
        if local
          acc[row["id"]] = local["id"]
          next
        end

        fresh = config[:scrub] ? scrub(row) : row.dup
        fresh = resolve([ fresh ], name, maps).first
        # Keep the id where it's free, so a dev copy lines up with production
        # wherever it can; where it isn't, take whatever this database gives.
        fresh.delete("id") if fresh["id"] && taken?(name, fresh["id"])
        insert_rows(name, [ fresh ])
        acc[row["id"]] = fresh["id"] || db.select_value("SELECT last_insert_rowid()")
        inserted << acc[row["id"]]
      end

      @inserted ||= {}
      @inserted[name] = inserted
      map
    end

    # node_classes.parent_id points at another node class, so the map it needs
    # isn't finished until the table is. Rather than order the inserts around
    # that, point them afterwards.
    def fix_self_references(maps)
      (@inserted&.dig("node_classes") || []).each do |id|
        parent = rows("SELECT parent_id FROM node_classes WHERE id = ?", id).first&.fetch("parent_id")
        next if parent.nil?
        mapped = maps["node_classes"][parent]
        next if mapped.nil? || mapped == parent
        db.execute("UPDATE node_classes SET parent_id = #{db.quote(mapped)} WHERE id = #{db.quote(id)}")
      end
      @inserted = nil
    end

    # Point a table's rows at the local rows the maps name.
    def resolve(rows, name, maps)
      refs = REFERENCES[name] || {}
      rows.each do |row|
        refs.each do |column, table|
          next if row[column].nil? || maps[table].nil?
          row[column] = maps[table].fetch(row[column], row[column])
        end
      end
    end

    # A person arrives with their name and no way in: a random digest nobody
    # holds, not activated, not an admin. A real password hash is a credential,
    # and copying one into a development database is not part of copying a task.
    def scrub(row)
      row.merge(
        "password_digest" => BCrypt::Password.create(SecureRandom.hex(32)),
        "admin" => false, "activated" => false, "activated_at" => nil,
        "reset_digest" => nil, "reset_sent_at" => nil,
        "invite_digest" => nil, "access_digest" => nil
      )
    end

    def taken?(table, id)
      rows("SELECT 1 FROM #{db.quote_table_name(table)} WHERE id = ?", id).any?
    end
  end
end
