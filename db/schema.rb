# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_08_20_210500) do
  create_table "actions", force: :cascade do |t|
    t.bigint "client_time"
    t.datetime "created_at", null: false
    t.integer "kit_id"
    t.string "name"
    t.integer "task_id"
    t.integer "user_id"
    t.index ["kit_id"], name: "index_actions_on_kit_id"
    t.index ["task_id"], name: "index_actions_on_task_id"
    t.index ["user_id"], name: "index_actions_on_user_id"
  end

  create_table "annotations", force: :cascade do |t|
    t.integer "begi"
    t.decimal "begr"
    t.datetime "created_at", null: false
    t.string "docid"
    t.integer "endi"
    t.decimal "endr"
    t.integer "iid"
    t.integer "kit_id"
    t.integer "last_iid"
    t.string "message"
    t.integer "parent_id"
    t.integer "source_id"
    t.integer "task_id"
    t.text "text"
    t.integer "transaction_id"
    t.integer "tree_id"
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.text "value"
    t.index ["kit_id"], name: "index_annotations_on_kit_id"
    t.index ["parent_id"], name: "index_annotations_on_parent_id"
    t.index ["task_id"], name: "index_annotations_on_task_id"
    t.index ["transaction_id"], name: "index_annotations_on_transaction_id"
    t.index ["tree_id"], name: "index_annotations_on_tree_id"
    t.index ["user_id"], name: "index_annotations_on_user_id"
  end

  create_table "class_defs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "def"
    t.string "name", limit: 255
    t.integer "original_id"
    t.datetime "updated_at", null: false
  end

  create_table "features", force: :cascade do |t|
    t.string "category"
    t.datetime "created_at", null: false
    t.text "description"
    t.string "label"
    t.string "name"
    t.datetime "updated_at", null: false
    t.string "value"
  end

  create_table "graph_arcs", force: :cascade do |t|
    t.integer "arc_node_iid"
    t.integer "beg_iid"
    t.datetime "created_at", null: false
    t.integer "end_iid"
    t.integer "iid", null: false
    t.string "name"
    t.integer "tree_id", null: false
    t.datetime "updated_at", null: false
    t.index ["tree_id", "beg_iid"], name: "index_graph_arcs_on_tree_id_and_beg_iid"
    t.index ["tree_id", "end_iid"], name: "index_graph_arcs_on_tree_id_and_end_iid"
    t.index ["tree_id", "iid"], name: "index_graph_arcs_on_tree_id_and_iid", unique: true
  end

  create_table "graph_labels", force: :cascade do |t|
    t.integer "arc_iid", null: false
    t.datetime "created_at", null: false
    t.integer "iid", null: false
    t.string "name"
    t.integer "tree_id", null: false
    t.datetime "updated_at", null: false
    t.text "value"
    t.index ["tree_id", "arc_iid"], name: "index_graph_labels_on_tree_id_and_arc_iid"
    t.index ["tree_id", "iid"], name: "index_graph_labels_on_tree_id_and_iid", unique: true
  end

  create_table "graph_nodes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "docid"
    t.integer "iid", null: false
    t.integer "n_iid"
    t.decimal "time", precision: 12, scale: 6
    t.integer "tree_id", null: false
    t.datetime "updated_at", null: false
    t.index ["tree_id", "iid"], name: "index_graph_nodes_on_tree_id_and_iid", unique: true
    t.index ["tree_id", "time"], name: "index_graph_nodes_on_tree_id_and_time"
  end

  create_table "group_users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "group_id"
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.index ["group_id", "user_id"], name: "index_group_users_on_group_id_and_user_id", unique: true
  end

  create_table "groups", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name"
    t.datetime "updated_at", null: false
  end

  create_table "guides", force: :cascade do |t|
    t.boolean "active"
    t.boolean "complete"
    t.integer "currentstep"
    t.boolean "dismissed"
    t.integer "firststep"
    t.string "misc"
    t.string "name"
    t.integer "nsteps"
    t.datetime "updated_at"
    t.integer "user_id"
  end

  create_table "imported_arcs", force: :cascade do |t|
    t.decimal "beg", precision: 12, scale: 6
    t.integer "beg_node_id", null: false
    t.datetime "created_at", null: false
    t.decimal "end", precision: 12, scale: 6
    t.integer "end_node_id", null: false
    t.integer "imported_graph_id", null: false
    t.string "name"
    t.datetime "updated_at", null: false
    t.index ["imported_graph_id", "beg"], name: "index_imported_arcs_on_imported_graph_id_and_beg"
    t.index ["imported_graph_id", "end"], name: "index_imported_arcs_on_imported_graph_id_and_end"
    t.index ["imported_graph_id", "name"], name: "index_imported_arcs_on_imported_graph_id_and_name"
  end

  create_table "imported_graphs", force: :cascade do |t|
    t.string "content_hash"
    t.datetime "created_at", null: false
    t.string "docid", null: false
    t.string "format"
    t.string "name", null: false
    t.string "source"
    t.string "stem"
    t.datetime "updated_at", null: false
    t.index ["docid", "name"], name: "index_imported_graphs_on_docid_and_name", unique: true
    t.index ["stem", "name"], name: "index_imported_graphs_on_stem_and_name"
  end

  create_table "imported_labels", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "imported_arc_id", null: false
    t.integer "imported_graph_id", null: false
    t.string "name"
    t.datetime "updated_at", null: false
    t.text "value"
    t.index ["imported_arc_id", "name"], name: "index_imported_labels_on_imported_arc_id_and_name"
    t.index ["imported_graph_id"], name: "index_imported_labels_on_imported_graph_id"
  end

  create_table "imported_nodes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "imported_graph_id", null: false
    t.decimal "time", precision: 12, scale: 6, null: false
    t.datetime "updated_at", null: false
    t.index ["imported_graph_id", "time"], name: "index_imported_nodes_on_imported_graph_id_and_time", unique: true
  end

  create_table "kit_batches", force: :cascade do |t|
    t.boolean "block"
    t.datetime "created_at", null: false
    t.integer "created_by"
    t.string "creation_type", limit: 255
    t.string "kit_creator", limit: 255
    t.string "message", limit: 255
    t.string "name", limit: 255
    t.integer "parallel_multiples"
    t.boolean "ready"
    t.integer "sequential_multiples"
    t.string "state", limit: 255
    t.integer "task_id"
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.index ["task_id"], name: "index_kit_batches_on_task_id"
    t.index ["user_id"], name: "index_kit_batches_on_user_id"
  end

  create_table "kit_creations", force: :cascade do |t|
    t.string "input", limit: 255
    t.integer "kit_batch_id"
    t.integer "kit_id"
    t.integer "sort_order"
    t.string "status", limit: 255
    t.integer "task_id"
    t.integer "user_id"
  end

  create_table "kit_states", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "kit_id"
    t.string "state"
    t.datetime "updated_at", null: false
    t.index ["kit_id", "state"], name: "index_kit_states_on_kit_id_and_state"
  end

  create_table "kit_stats", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.decimal "dvalue", precision: 10, scale: 3
    t.integer "ivalue"
    t.string "key", limit: 255
    t.integer "kit_id"
    t.string "svalue", limit: 255
    t.datetime "updated_at", null: false
    t.index ["dvalue"], name: "index_kit_stats_on_dvalue"
    t.index ["ivalue"], name: "index_kit_stats_on_ivalue"
    t.index ["kit_id", "key"], name: "index_kit_stats_on_kit_id_and_key", unique: true
    t.index ["svalue"], name: "index_kit_stats_on_svalue"
  end

  create_table "kit_types", force: :cascade do |t|
    t.integer "annotation_set_id"
    t.integer "config_id"
    t.text "constraints"
    t.datetime "created_at", null: false
    t.string "javascript"
    t.text "meta"
    t.string "name", limit: 255
    t.integer "node_class_id"
    t.integer "source_id"
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_kit_types_on_name", unique: true
  end

  create_table "kit_users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "kit_id"
    t.string "status", limit: 255
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.index ["kit_id", "user_id"], name: "index_kit_users_on_kit_id_and_user_id", unique: true
  end

  create_table "kit_values", force: :cascade do |t|
    t.string "key"
    t.integer "kit_id"
    t.string "value"
  end

  create_table "kits", force: :cascade do |t|
    t.text "broken_comment"
    t.datetime "created_at", null: false
    t.string "done_comment", limit: 255
    t.integer "dual_id"
    t.string "iid", limit: 255
    t.integer "kit_batch_id"
    t.integer "kit_type_id"
    t.integer "not_user_id"
    t.integer "orig_id"
    t.text "source"
    t.string "source_uid", limit: 255
    t.string "state", limit: 255
    t.decimal "sum", precision: 10, scale: 3
    t.integer "task_id"
    t.integer "time_spent"
    t.integer "tree_id"
    t.string "tree_oid", limit: 255
    t.string "uid", limit: 255
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.index ["kit_batch_id"], name: "index_kits_on_kit_batch_id"
    t.index ["kit_type_id"], name: "index_kits_on_kit_type_id"
    t.index ["not_user_id"], name: "index_kits_on_not_user_id"
    t.index ["state"], name: "index_kits_on_state"
    t.index ["task_id"], name: "index_kits_on_task_id"
    t.index ["tree_id"], name: "index_kits_on_tree_id"
    t.index ["uid"], name: "index_kits_on_uid"
    t.index ["user_id"], name: "index_kits_on_user_id"
  end

  create_table "node_classes", force: :cascade do |t|
    t.text "children"
    t.integer "class_def_id"
    t.text "constraints"
    t.datetime "created_at", null: false
    t.boolean "lazy"
    t.string "name", limit: 255
    t.integer "parent_id"
    t.string "span", limit: 255
    t.integer "style_id"
    t.datetime "updated_at", null: false
    t.text "value"
    t.index ["name"], name: "index_node_classes_on_name", unique: true
  end

  create_table "node_lists", force: :cascade do |t|
    t.text "children"
    t.integer "class_def_id"
    t.datetime "created_at", null: false
    t.string "name"
    t.datetime "updated_at", null: false
  end

  create_table "project_users", force: :cascade do |t|
    t.boolean "admin", default: false
    t.datetime "created_at", null: false
    t.boolean "owner", default: false
    t.integer "project_id"
    t.string "status"
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.index ["project_id", "user_id"], name: "index_project_users_on_project_id_and_user_id", unique: true
    t.index ["project_id"], name: "index_project_users_on_project_id"
    t.index ["user_id"], name: "index_project_users_on_user_id"
  end

  create_table "projects", force: :cascade do |t|
    t.text "about"
    t.datetime "created_at", null: false
    t.string "name", limit: 255
    t.string "subtitle"
    t.string "title"
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_projects_on_name", unique: true
  end

  create_table "sections", force: :cascade do |t|
    t.bigint "begn"
    t.decimal "btime", precision: 12, scale: 6
    t.bigint "endn"
    t.decimal "etime", precision: 12, scale: 6
    t.bigint "iid", null: false
    t.text "name"
    t.bigint "tree_id", null: false
    t.index ["tree_id", "begn"], name: "index_sections_on_tree_id_and_begn"
    t.index ["tree_id", "endn"], name: "index_sections_on_tree_id_and_endn"
    t.index ["tree_id", "iid"], name: "index_sections_on_tree_id_and_iid", unique: true
  end

  create_table "segments", force: :cascade do |t|
    t.bigint "begn"
    t.decimal "btime", precision: 12, scale: 6
    t.bigint "endn"
    t.decimal "etime", precision: 12, scale: 6
    t.bigint "iid", null: false
    t.text "speaker"
    t.text "text"
    t.bigint "tree_id", null: false
    t.index ["tree_id", "begn"], name: "index_segments_on_tree_id_and_begn"
    t.index ["tree_id", "endn"], name: "index_segments_on_tree_id_and_endn"
    t.index ["tree_id", "iid"], name: "index_segments_on_tree_id_and_iid", unique: true
  end

  create_table "servers", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name"
    t.datetime "updated_at", null: false
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "sources", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.time "duration"
    t.integer "enrollment_id"
    t.string "filename"
    t.string "format"
    t.string "languages"
    t.string "languages_other"
    t.string "participants"
    t.string "path"
    t.integer "task_id"
    t.string "uid"
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.string "voices"
    t.index ["enrollment_id"], name: "index_sources_on_enrollment_id"
    t.index ["user_id"], name: "index_sources_on_user_id"
  end

  create_table "states", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "kit_id"
    t.integer "task_user_id"
    t.datetime "updated_at", null: false
    t.index ["kit_id"], name: "index_states_on_kit_id"
    t.index ["task_user_id"], name: "index_states_on_task_user_id"
  end

  create_table "task_docids", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "docid", null: false
    t.integer "position"
    t.integer "task_id", null: false
    t.datetime "updated_at", null: false
    t.index ["task_id", "docid"], name: "index_task_docids_on_task_id_and_docid", unique: true
    t.index ["task_id", "position"], name: "index_task_docids_on_task_id_and_position"
  end

  create_table "task_user_states", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "state"
    t.integer "task_user_id"
    t.datetime "updated_at", null: false
    t.index ["task_user_id", "state"], name: "index_task_user_states_on_task_user_id_and_state"
  end

  create_table "task_users", force: :cascade do |t|
    t.boolean "admin", default: false
    t.datetime "created_at", null: false
    t.integer "kit_id"
    t.string "kit_oid", limit: 255
    t.integer "node_id"
    t.string "state", limit: 255
    t.integer "task_id"
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.index ["task_id", "user_id"], name: "index_task_users_on_task_id_and_user_id", unique: true
    t.index ["task_id"], name: "index_task_users_on_task_id"
    t.index ["user_id"], name: "index_task_users_on_user_id"
  end

  create_table "tasks", force: :cascade do |t|
    t.integer "check_count"
    t.datetime "created_at", null: false
    t.integer "cref_id"
    t.integer "data_set_id"
    t.datetime "deadline"
    t.integer "fund_id"
    t.bigint "game_variant_id"
    t.text "help"
    t.string "help_video", limit: 255
    t.integer "kit_type_id"
    t.integer "language_id"
    t.integer "lock_user_id"
    t.text "meta"
    t.string "name", limit: 255
    t.integer "node_class_id"
    t.integer "per_person_kit_limit"
    t.integer "project_id"
    t.string "status", limit: 255, default: "active"
    t.integer "task_type_id"
    t.text "token_counting_method"
    t.datetime "updated_at", null: false
    t.integer "workflow_id"
    t.index ["cref_id"], name: "index_tasks_on_cref_id"
    t.index ["fund_id"], name: "index_tasks_on_fund_id"
    t.index ["game_variant_id"], name: "index_tasks_on_game_variant_id"
    t.index ["language_id"], name: "index_tasks_on_language_id"
    t.index ["name", "project_id"], name: "index_tasks_on_name_and_project_id", unique: true
    t.index ["name"], name: "index_tasks_on_name"
    t.index ["project_id"], name: "index_tasks_on_project_id"
    t.index ["task_type_id"], name: "index_tasks_on_task_type_id"
  end

  create_table "trees", force: :cascade do |t|
    t.integer "class_def_id"
    t.datetime "created_at", null: false
    t.string "last_iid", limit: 255
    t.integer "locked"
    t.integer "source_id"
    t.string "status", limit: 255
    t.string "uid", limit: 255
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.integer "version"
    t.index ["class_def_id"], name: "index_trees_on_class_def_id"
    t.index ["source_id"], name: "index_trees_on_source_id"
    t.index ["status"], name: "index_trees_on_status"
    t.index ["uid"], name: "index_trees_on_uid", unique: true
  end

  create_table "user_defined_objects", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", limit: 255
    t.text "object"
    t.datetime "updated_at", null: false
  end

  create_table "users", force: :cascade do |t|
    t.datetime "access_created_at"
    t.integer "access_created_by"
    t.string "access_digest"
    t.boolean "activated", default: false
    t.datetime "activated_at"
    t.string "activation_digest"
    t.boolean "admin", default: false
    t.boolean "anon"
    t.datetime "confirmed_at"
    t.datetime "created_at", null: false
    t.integer "current_task_user_id"
    t.string "email_address", null: false
    t.string "invite_digest"
    t.datetime "invite_sent_at"
    t.integer "invite_sent_by"
    t.string "name"
    t.string "password_digest", null: false
    t.string "reset_digest"
    t.datetime "reset_sent_at"
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
  end

  create_table "versions", force: :cascade do |t|
    t.datetime "created_at"
    t.string "event", null: false
    t.bigint "item_id", null: false
    t.string "item_type", null: false
    t.text "object", limit: 1073741823
    t.text "object_changes", limit: 1073741823
    t.string "whodunnit"
    t.index ["item_type", "item_id"], name: "index_versions_on_item_type_and_item_id"
  end

  create_table "workflows", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.string "kit_states", limit: 255
    t.string "name", limit: 255
    t.string "type"
    t.datetime "updated_at", null: false
    t.string "user_states", limit: 255
    t.index ["name"], name: "index_workflows_on_name", unique: true
  end

  add_foreign_key "sessions", "users"
end
