class NewSetup < ActiveRecord::Migration[8.0]
  def change

    create_table "actions", force: :cascade do |t|
      t.integer "user_id"
      t.integer "task_id"
      t.integer "kit_id"
      t.string "name"
      t.bigint "client_time"
      t.datetime "created_at", null: false
      t.index ["kit_id"], name: "index_actions_on_kit_id"
      t.index ["task_id"], name: "index_actions_on_task_id"
      t.index ["user_id"], name: "index_actions_on_user_id"
    end

    create_table "annotations", force: :cascade do |t|
      t.integer "transaction_id"
      t.integer "parent_id"
      t.integer "user_id"
      t.integer "task_id"
      t.integer "kit_id"
      t.integer "tree_id"
      t.integer "iid"
      t.integer "last_iid"
      t.string "message"
      t.string "docid"
      t.integer "begi"
      t.integer "endi"
      t.text "value"
      t.text "text"
      t.decimal "begr"
      t.decimal "endr"
      t.integer "source_id"
      t.datetime "created_at", null: false
      t.datetime "updated_at", null: false
      t.index ["kit_id"], name: "index_annotations_on_kit_id"
      t.index ["parent_id"], name: "index_annotations_on_parent_id"
      t.index ["task_id"], name: "index_annotations_on_task_id"
      t.index ["transaction_id"], name: "index_annotations_on_transaction_id"
      t.index ["tree_id"], name: "index_annotations_on_tree_id"
      t.index ["user_id"], name: "index_annotations_on_user_id"
    end

    create_table "class_defs", force: :cascade do |t|
      t.string "name", limit: 255
      t.integer "original_id"
      t.text "def"
      t.datetime "created_at", null: false
      t.datetime "updated_at", null: false
    end

    create_table "features", force: :cascade do |t|
      t.string "category"
      t.string "name"
      t.string "value"
      t.string "label"
      t.text "description"
      t.datetime "created_at", null: false
      t.datetime "updated_at", null: false
    end

    create_table "group_users", force: :cascade do |t|
      t.integer "group_id"
      t.integer "user_id"
      t.datetime "created_at", null: false
      t.datetime "updated_at", null: false
    end

    create_table "groups", force: :cascade do |t|
      t.string "name"
      t.datetime "created_at", null: false
      t.datetime "updated_at", null: false
    end

    create_table "guides", force: :cascade do |t|
      t.string "name"
      t.integer "user_id"
      t.integer "firststep"
      t.integer "nsteps"
      t.integer "currentstep"
      t.boolean "active"
      t.boolean "complete"
      t.datetime "updated_at"
      t.boolean "dismissed"
      t.string "misc"
    end

    create_table "kit_batches", force: :cascade do |t|
      t.integer "user_id"
      t.integer "task_id"
      t.datetime "created_at", null: false
      t.datetime "updated_at", null: false
      t.string "state", limit: 255
      t.string "creation_type", limit: 255
      t.string "kit_creator", limit: 255
      t.string "name", limit: 255
      t.integer "created_by"
      t.boolean "block"
      t.boolean "ready"
      t.string "message", limit: 255
      t.integer "parallel_multiples"
      t.integer "sequential_multiples"
      t.index ["task_id"], name: "index_kit_batches_on_task_id"
      t.index ["user_id"], name: "index_kit_batches_on_user_id"
    end

    create_table "kit_creations", force: :cascade do |t|
      t.string "input", limit: 255
      t.integer "kit_id"
      t.integer "user_id"
      t.integer "task_id"
      t.string "status", limit: 255
      t.integer "kit_batch_id"
      t.integer "sort_order"
    end

    create_table "kit_states", force: :cascade do |t|
      t.integer "kit_id"
      t.string "state"
      t.datetime "created_at", null: false
      t.datetime "updated_at", null: false
      t.index ["kit_id", "state"], name: "index_kit_states_on_kit_id_and_state"
    end

    create_table "kit_stats", force: :cascade do |t|
      t.integer "kit_id"
      t.string "key", limit: 255
      t.string "svalue", limit: 255
      t.integer "ivalue"
      t.decimal "dvalue", precision: 10, scale: 3
      t.datetime "created_at", null: false
      t.datetime "updated_at", null: false
      t.index ["dvalue"], name: "index_kit_stats_on_dvalue"
      t.index ["ivalue"], name: "index_kit_stats_on_ivalue"
      t.index ["kit_id", "key"], name: "index_kit_stats_on_kit_id_and_key", unique: true
      t.index ["svalue"], name: "index_kit_stats_on_svalue"
    end

    create_table "kit_types", force: :cascade do |t|
      t.string "name", limit: 255
      t.integer "node_class_id"
      t.integer "source_id"
      t.datetime "created_at", null: false
      t.datetime "updated_at", null: false
      t.integer "config_id"
      t.integer "annotation_set_id"
      t.text "constraints"
      t.string "javascript"
      t.text "meta"
      t.index ["name"], name: "index_kit_types_on_name", unique: true
    end

    create_table "kit_users", force: :cascade do |t|
      t.integer "kit_id"
      t.integer "user_id"
      t.string "status", limit: 255
      t.datetime "created_at", null: false
      t.datetime "updated_at", null: false
      t.index ["kit_id", "user_id"], name: "index_kit_users_on_kit_id_and_user_id", unique: true
    end

    create_table "kit_values", force: :cascade do |t|
      t.integer "kit_id"
      t.string "key"
      t.string "value"
    end

    create_table "kits", force: :cascade do |t|
      t.datetime "created_at", null: false
      t.datetime "updated_at", null: false
      t.string "state", limit: 255
      t.integer "task_id"
      t.integer "user_id"
      t.integer "kit_type_id"
      t.text "broken_comment"
      t.text "source"
      t.string "uid", limit: 255
      t.integer "tree_id"
      t.string "tree_oid", limit: 255
      t.string "iid", limit: 255
      t.integer "kit_batch_id"
      t.integer "not_user_id"
      t.string "source_uid", limit: 255
      t.decimal "sum", precision: 10, scale: 3
      t.integer "time_spent"
      t.string "done_comment", limit: 255
      t.integer "dual_id"
      t.integer "orig_id"
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
      t.string "name", limit: 255
      t.integer "parent_id"
      t.text "children"
      t.datetime "created_at", null: false
      t.datetime "updated_at", null: false
      t.string "span", limit: 255
      t.integer "style_id"
      t.text "value"
      t.integer "class_def_id"
      t.boolean "lazy"
      t.text "constraints"
      t.index ["name"], name: "index_node_classes_on_name", unique: true
    end

    create_table "node_lists", force: :cascade do |t|
      t.integer "class_def_id"
      t.string "name"
      t.text "children"
      t.datetime "created_at", null: false
      t.datetime "updated_at", null: false
    end

    create_table "nodes", force: :cascade do |t|
      t.string "name"
      t.integer "user_id"
      t.integer "task_id"
      t.integer "parent_id"
      t.integer "parent_iid"
      t.integer "tree_id"
      t.integer "annotation_id"
      t.integer "index"
      t.integer "iid"
      t.integer "level"
      t.datetime "created_at", null: false
      t.datetime "updated_at", null: false
      t.index ["annotation_id"], name: "index_nodes_on_annotation_id"
      t.index ["parent_id"], name: "index_nodes_on_parent_id"
      t.index ["parent_iid"], name: "index_nodes_on_parent_iid"
      t.index ["tree_id", "iid"], name: "index_nodes_on_tree_id_and_iid", unique: true
    end

    create_table "project_users", force: :cascade do |t|
      t.integer "project_id"
      t.integer "user_id"
      t.datetime "created_at", null: false
      t.datetime "updated_at", null: false
      t.boolean "admin", default: false
      t.boolean "owner", default: false
      t.string "status"
      t.index ["project_id", "user_id"], name: "index_project_users_on_project_id_and_user_id", unique: true
      t.index ["project_id"], name: "index_project_users_on_project_id"
      t.index ["user_id"], name: "index_project_users_on_user_id"
    end

    create_table "projects", force: :cascade do |t|
      t.string "name", limit: 255
      t.datetime "created_at", null: false
      t.datetime "updated_at", null: false
      t.string "title"
      t.string "subtitle"
      t.text "about"
      t.index ["name"], name: "index_projects_on_name", unique: true
    end

    create_table "sections", force: :cascade do |t|
      t.bigint "tree_id", null: false
      t.bigint "iid", null: false
      t.bigint "begn"
      t.bigint "endn"
      t.decimal "btime", precision: 12, scale: 6
      t.decimal "etime", precision: 12, scale: 6
      t.text "name"
      t.index ["tree_id", "begn"], name: "index_sections_on_tree_id_and_begn"
      t.index ["tree_id", "endn"], name: "index_sections_on_tree_id_and_endn"
      t.index ["tree_id", "iid"], name: "index_sections_on_tree_id_and_iid", unique: true
    end

    create_table "segments", force: :cascade do |t|
      t.bigint "tree_id", null: false
      t.bigint "iid", null: false
      t.bigint "begn"
      t.bigint "endn"
      t.decimal "btime", precision: 12, scale: 6
      t.decimal "etime", precision: 12, scale: 6
      t.text "text"
      t.text "speaker"
      t.index ["tree_id", "begn"], name: "index_segments_on_tree_id_and_begn"
      t.index ["tree_id", "endn"], name: "index_segments_on_tree_id_and_endn"
      t.index ["tree_id", "iid"], name: "index_segments_on_tree_id_and_iid", unique: true
    end

    create_table "servers", force: :cascade do |t|
      t.string "name"
      t.datetime "created_at", null: false
      t.datetime "updated_at", null: false
    end

    create_table "sessions", force: :cascade do |t|
      t.integer "user_id", null: false
      t.string "ip_address"
      t.string "user_agent"
      t.datetime "created_at", null: false
      t.datetime "updated_at", null: false
      t.index ["user_id"], name: "index_sessions_on_user_id"
    end

    create_table "sources", force: :cascade do |t|
      t.string "uid"
      t.string "path"
      t.datetime "created_at", null: false
      t.datetime "updated_at", null: false
      t.string "format"
      t.string "filename"
      t.string "voices"
      t.string "participants"
      t.string "languages"
      t.time "duration"
      t.string "languages_other"
      t.integer "user_id"
      t.integer "enrollment_id"
      t.integer "task_id"
      t.index ["enrollment_id"], name: "index_sources_on_enrollment_id"
      t.index ["user_id"], name: "index_sources_on_user_id"
    end

    create_table "states", force: :cascade do |t|
      t.datetime "created_at", null: false
      t.datetime "updated_at", null: false
      t.integer "kit_id"
      t.integer "task_user_id"
      t.index ["kit_id"], name: "index_states_on_kit_id"
      t.index ["task_user_id"], name: "index_states_on_task_user_id"
    end

    create_table "task_user_states", force: :cascade do |t|
      t.integer "task_user_id"
      t.string "state"
      t.datetime "created_at", null: false
      t.datetime "updated_at", null: false
      t.index ["task_user_id", "state"], name: "index_task_user_states_on_task_user_id_and_state"
    end

    create_table "task_users", force: :cascade do |t|
      t.integer "task_id"
      t.integer "user_id"
      t.datetime "created_at", null: false
      t.datetime "updated_at", null: false
      t.string "state", limit: 255
      t.integer "node_id"
      t.boolean "admin", default: false
      t.integer "kit_id"
      t.string "kit_oid", limit: 255
      t.index ["task_id", "user_id"], name: "index_task_users_on_task_id_and_user_id", unique: true
      t.index ["task_id"], name: "index_task_users_on_task_id"
      t.index ["user_id"], name: "index_task_users_on_user_id"
    end

    create_table "tasks", force: :cascade do |t|
      t.string "name", limit: 255
      t.integer "project_id"
      t.datetime "created_at", null: false
      t.datetime "updated_at", null: false
      t.integer "node_class_id"
      t.integer "workflow_id"
      t.text "help"
      t.string "help_video", limit: 255
      t.integer "per_person_kit_limit"
      t.integer "kit_type_id"
      t.integer "check_count"
      t.integer "lock_user_id"
      t.text "token_counting_method"
      t.string "status", limit: 255, default: "active"
      t.integer "language_id"
      t.integer "task_type_id"
      t.datetime "deadline"
      t.integer "cref_id"
      t.integer "fund_id"
      t.bigint "game_variant_id"
      t.text "meta"
      t.integer "data_set_id"
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
      t.string "uid", limit: 255
      t.integer "class_def_id"
      t.integer "version"
      t.string "last_iid", limit: 255
      t.datetime "created_at", null: false
      t.datetime "updated_at", null: false
      t.integer "source_id"
      t.string "status", limit: 255
      t.integer "user_id"
      t.integer "locked"
      t.index ["class_def_id"], name: "index_trees_on_class_def_id"
      t.index ["source_id"], name: "index_trees_on_source_id"
      t.index ["status"], name: "index_trees_on_status"
      t.index ["uid"], name: "index_trees_on_uid", unique: true
    end

    create_table "user_defined_objects", force: :cascade do |t|
      t.string "name", limit: 255
      t.text "object"
      t.datetime "created_at", null: false
      t.datetime "updated_at", null: false
    end

    create_table "users", force: :cascade do |t|
      t.string "email_address", null: false
      t.string "password_digest", null: false
      t.datetime "created_at", null: false
      t.datetime "updated_at", null: false
      t.string "name"
      t.boolean "admin", default: false
      t.string "activation_digest"
      t.boolean "activated", default: false
      t.datetime "activated_at"
      t.string "reset_digest"
      t.datetime "reset_sent_at"
      t.integer "current_task_user_id"
      t.boolean "anon"
      t.datetime "confirmed_at"
      t.string "invite_digest"
      t.datetime "invite_sent_at"
      t.integer "invite_sent_by"
      t.index ["email_address"], name: "index_users_on_email_address", unique: true
    end

    create_table "versions", force: :cascade do |t|
      t.string "whodunnit"
      t.datetime "created_at"
      t.bigint "item_id", null: false
      t.string "item_type", null: false
      t.string "event", null: false
      t.text "object", limit: 1073741823
      t.text "object_changes", limit: 1073741823
      t.index ["item_type", "item_id"], name: "index_versions_on_item_type_and_item_id"
    end

    create_table "workflows", force: :cascade do |t|
      t.string "name", limit: 255
      t.string "user_states", limit: 255
      t.text "description"
      t.datetime "created_at", null: false
      t.datetime "updated_at", null: false
      t.string "kit_states", limit: 255
      t.string "type"
      t.index ["name"], name: "index_workflows_on_name", unique: true
    end

    add_foreign_key "sessions", "users"

  end
end
