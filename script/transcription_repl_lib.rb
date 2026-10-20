# Shared helpers for the transcription REPL scripts:
#   script/transcription_repl.rb  (manual: human drives the browser)
#   script/transcription_auto.rb  (automated: scripted Selenium gestures)
#
# Both scripts have identical setup, browser launch, sign-in, and dump+assert
# phases — they only differ in what happens between "browser is open" and
# "dump DB state". This module owns everything that's shared.

require "net/http"
require "uri"

module TranscriptionReplLib
  HOST     = ENV["HOST"] || "http://localhost:3001"
  WAV_PATH = "/test_tone_10s.wav"
  # JSON wrapper source (script/transcription_repl_wrapper.rb): points at the same
  # tone plus a TSV transcript, so the tool loads pre-populated. Both files live in
  # public/ and are served statically; the repl manifest patch maps the .json uid.
  WRAPPER_JSON_PATH = "/test_tone_10s.json"
  PASSWORD = "password123"

  module_function

  # ── server reachability ─────────────────────────────────────────────────
  def server_running?
    uri = URI.parse("#{HOST}/up")
    Net::HTTP.start(uri.host, uri.port, open_timeout: 1, read_timeout: 1) do |http|
      http.request(Net::HTTP::Get.new(uri.request_uri)).code == "200"
    end
  rescue StandardError
    false
  end

  def require_server!
    return if ENV["SKIP_SERVER_CHECK"]
    return if server_running?
    abort <<~MSG

      The repl server isn't reachable at #{HOST}.

      Start it in another terminal first:

          bin/repl

      then re-run this script.

    MSG
  end

  # ── first-run DB bootstrap ──────────────────────────────────────────────
  # If the repl DB is empty, load schema and run db/seeds.rb. The seed file
  # creates SimpleTranscription before ArcTranscription, so ArcTranscription's
  # class_def gets id=2; work.js gates the maintranscription.svelte component
  # on the ArcTranscription class def.
  def bootstrap_db_if_needed!
    return if ActiveRecord::Base.connection.table_exists?("users")
    puts "==> #{Rails.env} DB is empty — loading schema from db/schema.rb..."
    ActiveRecord::Schema.verbose = false
    load Rails.root.join("db/schema.rb").to_s
    # db/seeds.rb writes the Annotation id=0 placeholder, base NodeClasses,
    # Workflows, and the canonical Transcription Project/Task/KitType plus
    # ArcTranscription/SimpleTranscription ClassDefs.
    puts "==> Loading db/seeds.rb..."
    load Rails.root.join("db/seeds.rb").to_s
  end

  # ── data setup ──────────────────────────────────────────────────────────
  # Idempotent. Returns { user:, project:, task:, kit:, tree:, task_user: }.
  # Sweeps prior kits on the task so Workflow#assign_kit picks our fresh kit.
  #
  # Defaults reproduce the plain-audio kit (script/transcription_auto.rb). Pass a
  # different source_uid + extra_constraints (and a name_suffix / kit_type_name to
  # keep the fixtures isolated) for the JSON-wrapper variant.
  def setup_data(source_uid: WAV_PATH, source_filename: "test_tone_10s.wav",
                 kit_type_name: "transcription_repl", name_suffix: "",
                 extra_constraints: {})
    user = User.find_or_create_by!(email_address: "repl@example.com") do |u|
      u.name = "replannotator"
      u.password = PASSWORD
      u.password_confirmation = PASSWORD
    end
    user.update!(activated: true, activated_at: Time.now) unless user.activated?

    class_def = ClassDef.where(name: "ArcTranscription").first_or_create!
    root_nc = NodeClass.where(name: "Root").first_or_create!
    arc_root = NodeClass.where(name: "ArcTranscription:Root").first_or_create do |nc|
      nc.parent = root_nc
    end
    if arc_root.class_def_id.nil? || arc_root.parent_id.nil?
      arc_root.update!(class_def: class_def, parent: root_nc)
    end

    workflow = Workflow.where(name: "Orderly").first_or_create!
    kit_type = KitType.where(name: kit_type_name).first_or_create do |kt|
      kt.node_class = arc_root
    end
    # Force the constraints to the test's expected set on every run rather than
    # only on first_or_create — if a prior run set a different shape, we want
    # to reset to the canonical one. `export_transcript` is required for the
    # transcription tool's download trigger to render (controls.svelte:197).
    # extra_constraints lets the wrapper variant add e.g. import_transcript_auto.
    kit_type.update!(
      node_class: arc_root,
      constraints: {
        "web_audio" => "web_audio",
        "show_source" => "show_source",
        "export_transcript" => "export_transcript",
      }.merge(extra_constraints),
    )

    project = Project.where(name: "transcription_repl_project#{name_suffix}").first_or_create!
    task = Task.where(name: "transcription_repl_task#{name_suffix}", project: project).first_or_create do |t|
      t.workflow = workflow
      t.kit_type = kit_type
      t.status = "active"
    end
    ProjectUser.where(project: project, user: user).first_or_create.update!(admin: true, owner: true)
    TaskUser.where(task: task, user: user).first_or_create.update!(admin: true)

    prior_count = Kit.where(task: task).count
    Kit.where(task: task).find_each do |k|
      Tree.where(id: k.tree_id).destroy_all if k.tree_id
      k.destroy
    end
    puts "  swept #{prior_count} prior kit(s) on the repl task" if prior_count > 0

    # Don't pre-create a Tree. Leave kit.tree_id nil so Workflow#assign_kit's
    # `if @kit.tree_id.nil?` branch (workflow.rb:274) fires and runs the
    # canonical Kit#create_tree → KitType#new_root → ClassDef#new_root +
    # KitType#create_with_json path. That path writes the first Annotation
    # (message='new', last_iid=0) the same way production does for any
    # admin-created kit on its first /workflows/X/work visit. The caller
    # should reload the kit after the work page mounts and read kit.tree.
    kit = Kit.create!(
      task: task, kit_type: kit_type, state: "unassigned",
      source: { "uid" => source_uid, "id" => source_uid, "type" => "audio", "filename" => source_filename },
      source_uid: source_uid,
    )
    task_user = TaskUser.find_by!(task: task, user: user)
    task_user.update!(state: "needs_kit", kit_oid: nil)

    puts "  user      ##{user.id}  #{user.email_address} / #{PASSWORD}"
    puts "  project   ##{project.id}  #{project.name}"
    puts "  task      ##{task.id}    workflow=#{workflow.name} kit_type=#{kit_type.name}"
    puts "  task_user ##{task_user.id}"
    puts "  kit       ##{kit.id}     uid=#{kit.uid}  source=#{source_uid}  (tree to be created by Workflow#assign_kit)"

    { user: user, project: project, task: task, kit: kit, tree: nil, task_user: task_user, workflow: workflow }
  end

  # ── browser lifecycle ───────────────────────────────────────────────────
  # Blocks until the human closes the browser window.
  #
  # Polling for an exception isn't enough. Closing the last window ends the
  # WebDriver session in some setups — headless Chrome exits, and the next call
  # raises InvalidSessionIdError — but leaves it alive in others. A real,
  # non-headless Chrome on macOS outlives its last window, so window_handles
  # just returns [] and never raises; a loop waiting only for an exception spins
  # forever. Treat an empty list as closed too.
  def wait_for_browser_close(driver, interval: 0.5)
    loop do
      begin
        return if driver.window_handles.empty?
        sleep interval
      rescue Selenium::WebDriver::Error::NoSuchWindowError, Selenium::WebDriver::Error::InvalidSessionIdError
        return
      rescue Selenium::WebDriver::Error::WebDriverError => e
        return if e.message.match?(/no such (window|driver)|invalid session|disconnect|target window/i)
        raise
      end
    end
  end

  # Selenium Manager prefers chromedriver on PATH (often a stale Homebrew copy).
  # Run selenium-manager directly with Homebrew/local-bin scrubbed from PATH so
  # it returns its own cached, version-matched driver.
  def resolve_managed_chromedriver
    require "json"
    platform_dir = case RUBY_PLATFORM
                   when /darwin/ then "macos"
                   when /mingw|mswin/ then "windows"
                   else "linux"
                   end
    suffix = platform_dir == "windows" ? ".exe" : ""
    sm_bin = File.join(Gem.loaded_specs["selenium-webdriver"].full_gem_path, "bin", platform_dir, "selenium-manager#{suffix}")
    scrubbed_path = ENV["PATH"].to_s.split(File::PATH_SEPARATOR)
                                     .reject { |d| d =~ %r{/(homebrew|usr/local)/bin\z} }
                                     .join(File::PATH_SEPARATOR)
    output = IO.popen({ "PATH" => scrubbed_path }, [sm_bin, "--browser", "chrome", "--output", "json"], err: File::NULL, &:read)
    path = JSON.parse(output).dig("result", "driver_path")
    path if path && !path.empty?
  rescue StandardError
    nil
  end

  # ── browser launch + sign-in ────────────────────────────────────────────
  def launch_browser_signed_in(user:, task_user:, task:)
    require "selenium-webdriver"
    options = Selenium::WebDriver::Chrome::Options.new
    options.add_argument("--window-size=1400,1000")
    # HEADLESS=1 for the automated scripts when you don't want a window taking
    # over the screen. The interactive ones need a real window, so they ignore
    # it by simply not being run that way.
    if ENV["HEADLESS"]
      options.add_argument("--headless=new")
      options.add_argument("--disable-gpu")
    end

    managed_path = resolve_managed_chromedriver
    if managed_path
      service = Selenium::WebDriver::Service.chrome(path: managed_path)
      driver = Selenium::WebDriver.for :chrome, options: options, service: service
    else
      warn "[warn] could not resolve a managed chromedriver via selenium-manager; falling back to PATH"
      driver = Selenium::WebDriver.for :chrome, options: options
    end

    driver.navigate.to "#{HOST}/session/new"
    driver.find_element(name: "email_address").send_keys(user.email_address)
    driver.find_element(name: "password").send_keys(PASSWORD)
    driver.find_element(name: "commit").click
    sleep 1

    work_url = "#{HOST}/workflows/#{task_user.id}/work/#{task.workflow_id}"
    puts "  -> #{work_url}"
    driver.navigate.to work_url
    driver
  end

  # ── dump ─────────────────────────────────────────────────────────────────
  # Resolves which kit the workflow actually assigned (may differ from the one
  # we created if anything went sideways) and prints its full DB state (kit,
  # task_user, annotations, nodes, KitState transitions). Returns
  # [dump_kit, dump_tree] for callers that run further checks or their own
  # reporting — shared by dump_and_exit and the manual wrapper harness.
  def dump_state(kit:, tree:, task_user:)
    task_user.reload
    assigned_kit = task_user.kit_oid.present? ? Kit.find_by(uid: task_user.kit_oid) : nil
    dump_kit  = assigned_kit || kit.reload
    dump_tree = dump_kit.tree || tree

    puts ""
    puts "==> Dumping DB state for kit ##{dump_kit.id} (uid=#{dump_kit.uid.inspect}) ..."
    if assigned_kit && assigned_kit.id != kit.id
      puts "  (note: workflow assigned a different kit — original ##{kit.id} was unused)"
    end

    puts ""
    puts "Kit ##{dump_kit.id}"
    puts "  uid          = #{dump_kit.uid.inspect}"
    puts "  state        = #{dump_kit.state.inspect}"
    puts "  user_id      = #{dump_kit.user_id.inspect}"
    puts "  source_uid   = #{dump_kit.source_uid.inspect}"
    puts "  tree_id      = #{dump_kit.tree_id.inspect}"
    puts "  done_comment = #{dump_kit.done_comment.inspect}"
    puts "  broken_comment = #{dump_kit.broken_comment.inspect}"

    puts ""
    puts "TaskUser ##{task_user.id}"
    puts "  state    = #{task_user.state.inspect}"
    puts "  kit_oid  = #{task_user.kit_oid.inspect}"

    annotations = Annotation.where(kit_id: dump_kit.id).order(:id)
    puts ""
    puts "Annotations (#{annotations.count} rows):"
    annotations.each do |a|
      parts = {
        id: a.id, message: a.message, iid: a.iid,
        last_iid: a.last_iid, parent_id: a.parent_id,
        value: a.value.to_s[0, 60], docid: a.docid,
        begr: a.begr, endr: a.endr, begi: a.begi, endi: a.endi
      }.compact_blank
      puts "  " + parts.map { |k, v| "#{k}=#{v.inspect}" }.join("  ")
    end

    puts ""
    if dump_tree
      # The nodes table isn't written any more; the graph is replayed from the
      # annotations above (NodeDerivation), which is what the app itself reads.
      derived = NodeDerivation.for_tree(dump_tree.id)
      puts "Nodes derived for tree ##{dump_tree.id} (#{derived.nodes.size}):"
      derived.nodes.each_value do |n|
        puts "  iid=#{n[:iid]}  name=#{n[:name].inspect}  parent_iid=#{n[:parent_iid].inspect}  ann=#{n[:annotation_id]}"
      end
      derived.anomalies.each { |a| puts "  ! #{a}" }
    else
      puts "Nodes: (no tree yet — kit was never assigned/opened)"
    end

    states = KitState.where(kit_id: dump_kit.id).order(:id)
    puts ""
    puts "KitState transitions (#{states.count}):"
    states.each do |s|
      puts "  #{s.created_at.iso8601}  -> #{s.state}"
    end

    [dump_kit, dump_tree]
  end

  # ── dump + structural checks ────────────────────────────────────────────
  # Dumps state, then runs the DB-shape + transcription structure checks (plus
  # any extra_checks) and exits 0 (PASS) or 1 (FAIL). `extra_checks` is an
  # optional array of `{ label:, passes:, failures: }` hashes for assertions
  # that don't fit the DB-shape mold (e.g. transcription_auto.rb's
  # download-via-dashboard verification); they print in their own section and
  # contribute to the PASS/FAIL totals.
  def dump_and_exit(kit:, tree:, task_user:, extra_checks: [])
    dump_kit, dump_tree = dump_state(kit: kit, tree: tree, task_user: task_user)

    dump_all_tables if ENV["DUMP_ALL"] == "1"

    db_failures, db_passes        = check_database(kit: dump_kit, tree: dump_tree, task_user: task_user)
    tx_failures, tx_warnings      = check_transcription(dump_kit, dump_tree)

    puts ""
    puts "==> Database checks (all rows the flow created or depends on)"
    db_passes.each { |p| puts "  ✓ #{p}" }
    db_failures.each { |f| puts "  ✗ #{f}" }

    puts ""
    puts "==> Transcription structure checks"
    tx_warnings.each { |w| puts "  ⚠️  #{w}" }
    if tx_failures.empty?
      puts "  ✓ transcription has the expected shape (segment + Arc with time + Text with content)"
    else
      tx_failures.each { |f| puts "  ✗ #{f}" }
    end

    extra_checks.each do |section|
      puts ""
      puts "==> #{section[:label]}"
      Array(section[:passes]).each   { |p| puts "  ✓ #{p}" }
      Array(section[:failures]).each { |f| puts "  ✗ #{f}" }
    end
    extra_passes_total   = extra_checks.sum { |s| Array(s[:passes]).size }
    extra_failures_total = extra_checks.sum { |s| Array(s[:failures]).size }

    total_failures = db_failures.size + tx_failures.size + extra_failures_total
    total_passes   = db_passes.size + extra_passes_total
    puts ""
    if total_failures.zero?
      puts "==> PASS — #{total_passes} check#{total_passes == 1 ? "" : "s"} + transcription structure all green."
      puts "==> Done. Run the script again to start a fresh kit/tree."
      exit 0
    else
      breakdown = ["#{db_failures.size} database", "#{tx_failures.size} structure"]
      breakdown << "#{extra_failures_total} extra" if extra_failures_total > 0
      puts "==> FAIL — #{total_failures} issue#{total_failures == 1 ? "" : "s"} (#{breakdown.join(", ")})."
      exit 1
    end
  end

  # SELECT * across every user-defined table, formatted for the terminal.
  # Triggered by `DUMP_ALL=1`. Skips Rails-internal bookkeeping tables.
  # Long string values are truncated to keep rows on one line each.
  def dump_all_tables
    skip = %w[schema_migrations ar_internal_metadata]
    conn = ActiveRecord::Base.connection
    tables = (conn.tables - skip).sort

    puts ""
    puts "=" * 72
    puts "== FULL DATABASE DUMP — #{tables.size} tables (DUMP_ALL=1)"
    puts "=" * 72

    tables.each do |table|
      qt   = conn.quote_table_name(table)
      cnt  = conn.select_value("SELECT COUNT(*) FROM #{qt}").to_i
      puts ""
      puts "── #{table} (#{cnt} #{cnt == 1 ? "row" : "rows"})"
      next if cnt.zero?

      # Order by id when available so output is stable across runs; fall back
      # to natural order for tables without an id column.
      has_id = conn.columns(table).any? { |c| c.name == "id" }
      sql = "SELECT * FROM #{qt}"
      sql += " ORDER BY id" if has_id
      conn.select_all(sql).each do |row|
        parts = row.map do |k, v|
          str =
            case v
            when nil          then "nil"
            when String       then v.length > 80 ? "#{v[0, 77].inspect}…" : v.inspect
            else                   v.inspect
            end
          "#{k}=#{str}"
        end
        puts "  " + parts.join("  ")
      end
    end
    puts ""
    puts "=" * 72
  end

  # Walks the full chain of records the flow either creates or depends on and
  # asserts each is present with the expected shape. Returns [failures, passes]
  # where `passes` is a list of human-readable assertion summaries (so the
  # output enumerates exactly what was verified, not just what failed).
  def check_database(kit:, tree:, task_user:)
    failures = []
    passes   = []
    expect = ->(label, ok) { ok ? passes << label : failures << label }

    # ── User ──
    user = User.find_by(email_address: "repl@example.com")
    expect.call("User repl@example.com exists",                           !user.nil?)
    expect.call("  …name=replannotator",                                  user && user.name == "replannotator")
    expect.call("  …activated=true",                                      user && user.activated?)

    # ── ClassDef ── (id=2 because db/seeds.rb creates SimpleTranscription first)
    arc_cd = ClassDef.find_by(name: "ArcTranscription")
    expect.call("ClassDef ArcTranscription exists",                       !arc_cd.nil?)
    expect.call("  …id=2 (db/seeds.rb creates SimpleTranscription at id=1)", arc_cd && arc_cd.id == 2)

    # ── NodeClasses ──
    root_nc = NodeClass.find_by(name: "Root")
    arc_root = NodeClass.find_by(name: "ArcTranscription:Root")
    expect.call("NodeClass Root exists",                                  !root_nc.nil?)
    expect.call("NodeClass ArcTranscription:Root exists",                 !arc_root.nil?)
    expect.call("  …parent=Root",                                         arc_root && root_nc && arc_root.parent_id == root_nc.id)
    expect.call("  …class_def=ArcTranscription",                          arc_root && arc_cd && arc_root.class_def_id == arc_cd.id)

    # ── Workflow ──
    workflow = Workflow.find_by(name: "Orderly")
    expect.call("Workflow Orderly exists",                                !workflow.nil?)

    # ── KitType ──
    kit_type = KitType.find_by(name: "transcription_repl")
    expect.call("KitType transcription_repl exists",                      !kit_type.nil?)
    expect.call("  …node_class=ArcTranscription:Root",                    kit_type && arc_root && kit_type.node_class_id == arc_root.id)
    expect.call("  …has web_audio + show_source + export_transcript constraints",
      kit_type && kit_type.constraints.is_a?(Hash) &&
        kit_type.constraints["web_audio"] == "web_audio" &&
        kit_type.constraints["show_source"] == "show_source" &&
        kit_type.constraints["export_transcript"] == "export_transcript")

    # ── Project ──
    project = Project.find_by(name: "transcription_repl_project")
    expect.call("Project transcription_repl_project exists",              !project.nil?)

    # ── Task ──
    task = Task.find_by(name: "transcription_repl_task", project_id: project&.id)
    expect.call("Task transcription_repl_task exists",                    !task.nil?)
    expect.call("  …workflow=Orderly",                                    task && workflow && task.workflow_id == workflow.id)
    expect.call("  …kit_type=transcription_repl",                         task && kit_type && task.kit_type_id == kit_type.id)
    expect.call("  …status=active",                                       task && task.status == "active")

    # ── ProjectUser ──
    pu = ProjectUser.find_by(project_id: project&.id, user_id: user&.id)
    expect.call("ProjectUser (project↔user) exists",                      !pu.nil?)
    expect.call("  …admin=true",                                          pu && pu.admin)
    expect.call("  …owner=true",                                          pu && pu.owner)

    # ── TaskUser ──
    tu = TaskUser.find_by(task_id: task&.id, user_id: user&.id)
    expect.call("TaskUser (task↔user) exists",                            !tu.nil?)
    expect.call("  …kit_oid set after work assignment",                   tu && tu.kit_oid.present?)

    # ── Tree ──
    expect.call("Tree exists for kit",                                    !tree.nil?)
    expect.call("  …class_def=ArcTranscription",                          tree && arc_cd && tree.class_def_id == arc_cd.id)
    # ClassDef#new_root sets tree.version = class_def.original_id (which is
    # class_def.id after the first call). We don't pin a specific number.
    expect.call("  …version is set (bootstrapped via ClassDef#new_root)",  tree && !tree.version.nil?)

    # ── Kit ──
    expect.call("Kit exists",                                             !kit.nil?)
    # The manual REPL leaves the kit at 'assigned' (user closes browser without
    # clicking Done); transcription_auto.rb drives the Done flow so it should
    # reach 'done'. Either is a successful workflow transition.
    expect.call("  …state in [assigned, done]",                           kit && %w[assigned done].include?(kit.state))
    expect.call("  …source_uid=#{WAV_PATH}",                              kit && kit.source_uid == WAV_PATH)
    expect.call("  …source hash includes uid+filename",
      kit && kit.source.is_a?(Hash) &&
        (kit.source["uid"] || kit.source[:uid]) == WAV_PATH &&
        ((kit.source["filename"] || kit.source[:filename]).to_s.end_with?(".wav")))
    expect.call("  …tree_id linked",                                      kit && tree && kit.tree_id == tree.id)

    # ── KitState transitions ── (workflow assignment writes one; the Done
    # gesture writes another). The list should contain 'assigned' at minimum,
    # and 'done' if the run drove the close-kit dialog.
    states = kit ? KitState.where(kit_id: kit.id).pluck(:state) : []
    expect.call("KitState recorded ≥1 transition for the kit",            states.any?)
    expect.call("  …'assigned' transition recorded",                      states.include?("assigned"))
    if kit && kit.state == "done"
      expect.call("  …'done' transition recorded (Done flow)",            states.include?("done"))
    end

    # ── Annotations (post-flow) ──
    anns = kit ? Annotation.where(kit_id: kit.id) : Annotation.none
    expect.call("Annotations: ≥1 row for the kit",                        anns.count >= 1)
    valid_msgs = %w[new add change delete done broken skip]
    bad_msgs = anns.pluck(:message).uniq - valid_msgs
    msg_label = "  …all messages in #{valid_msgs.inspect}"
    msg_label += " (got unknown: #{bad_msgs.inspect})" if bad_msgs.any?
    expect.call(msg_label,                                                anns.any? && bad_msgs.empty?)
    expect.call("  …every Annotation belongs to our tree",                anns.any? && anns.where.not(tree_id: tree&.id).none?)
    # The first Annotation should be the message='new' tree-creation marker
    # written by KitType#create_with_json on the production path.
    first = anns.order(:id).first
    expect.call("  …first Annotation has message='new' (tree-creation marker)",
      first && first.message == "new" && first.last_iid == 0)
    if kit && kit.state == "done"
      expect.call("  …'done' Annotation recorded",                        anns.where(message: "done").exists?)
    end

    # ── Nodes (post-flow) ──
    # Derived from the annotation log rather than read from the nodes table,
    # which nothing writes any more — this is the graph the app serves.
    derived = tree ? NodeDerivation.for_tree(tree.id) : nil
    nodes = derived ? derived.nodes.values : []
    expect.call("Nodes: ≥1 node derived for the tree",                    nodes.length >= 1)
    expect.call("  …≥1 SegmentListItem node",                            nodes.count { |n| n[:name] == "SegmentListItem" } >= 1)
    expect.call("  …the replay reports no anomalies",                    derived.nil? || derived.ok?)
    # Every node named as a SegmentListItem child should resolve back to a
    # derived node in this tree (no dangling parent_iid references).
    seg_iids = nodes.select { |n| n[:name] == "SegmentListItem" }.map { |n| n[:iid] }
    if seg_iids.any?
      child_parent_iids = nodes.map { |n| n[:parent_iid] }.compact.uniq
      expect.call("  …every SegmentListItem has at least one child node",
        (seg_iids - child_parent_iids).empty?)
    end

    # ── Speaker (set via Ctrl+S → 'n' → type → Enter on a segment) ──
    # The Speaker Node is created when the segment is added (it's a SegmentListItem
    # child); the assignment then writes a 'change' Annotation with the speaker
    # name as `value`. We assert at least one Speaker has a non-blank value.
    speaker_iids = nodes.select { |n| n[:name] == "Speaker" }.map { |n| n[:iid] }
    if speaker_iids.any?
      named_speakers = anns.where(iid: speaker_iids).where.not(value: [nil, ""]).count
      expect.call("Speaker: ≥1 Speaker node has a named-value annotation",  named_speakers >= 1)
    end

    # ── Section (opened via Ctrl+[ → 'n' → type → Enter) ──
    # Opening a section creates a SectionListItem with Arc + Name children
    # (modification1.js#add_section). The Name annotation
    # carries the section label.
    section_count = nodes.count { |n| n[:name] == "SectionListItem" }
    if section_count >= 1
      expect.call("SectionListItem: ≥1 row created",                        section_count >= 1)
      name_iids = nodes.select { |n| n[:name] == "Name" }.map { |n| n[:iid] }
      named_sections = anns.where(iid: name_iids).where.not(value: [nil, ""]).count
      expect.call("  …Section's Name child has a non-blank value",          named_sections >= 1)
    end

    # ── Sessions ── (sign-in created one)
    sess = user ? Session.where(user_id: user.id) : Session.none
    expect.call("Session row created at sign-in (≥1)",                    sess.any?)

    [failures, passes]
  end

  # Asserts the shape of "a valid transcription" without caring about specific
  # ids, timestamps, or text content. Each check explains what it's looking
  # for so a failure tells you what was missing in the session.
  def check_transcription(kit, tree)
    failures = []
    warnings = []

    unless %w[assigned done].include?(kit.state)
      failures << "kit.state should be 'assigned' or 'done' (got #{kit.state.inspect}) — workflow assignment didn't complete"
    end

    if Annotation.where(kit_id: kit.id).none?
      failures << "no Annotation rows were created — the JS save path never reached AnnotationsController#create"
      return [failures, warnings]
    end

    derived = NodeDerivation.for_tree(tree.id)
    by_name = ->(name) { derived.nodes.each_value.select { |n| n[:name] == name } }
    child_of = ->(parent_iid, name) do
      derived.nodes.each_value.find { |n| n[:parent_iid] == parent_iid && n[:name] == name }
    end

    failures.concat(derived.anomalies)

    segments = by_name.call("SegmentListItem")
    if segments.empty?
      failures << "no SegmentListItem nodes — at least one transcribed segment is expected"
      return [failures, warnings]
    end

    segments.each do |seg|
      arc     = child_of.call(seg[:iid], "Arc")
      text    = child_of.call(seg[:iid], "Text")
      speaker = child_of.call(seg[:iid], "Speaker")

      unless arc
        failures << "SegmentListItem iid=#{seg[:iid]} is missing its Arc child"
        next
      end
      unless text
        failures << "SegmentListItem iid=#{seg[:iid]} is missing its Text child"
        next
      end
      warnings << "SegmentListItem iid=#{seg[:iid]} has no Speaker child" unless speaker

      arc_ann = Annotation.where(tree_id: tree.id, iid: arc[:iid]).where("begi IS NOT NULL OR begr IS NOT NULL").last
      failures << "Arc iid=#{arc[:iid]} has no time set (no annotation with begi or begr)" unless arc_ann

      text_ann = Annotation.where(tree_id: tree.id, iid: text[:iid]).where.not(value: [nil, ""]).last
      failures << "Text iid=#{text[:iid]} has no transcribed content (no annotation with non-empty value)" unless text_ann
    end

    by_name.call("NListItem").each do |nl|
      n_node = child_of.call(nl[:iid], "N")
      unless n_node
        warnings << "NListItem iid=#{nl[:iid]} is missing its N child"
        next
      end
      n_ann = Annotation.where(tree_id: tree.id, iid: n_node[:iid]).where.not(begr: nil).last
      warnings << "N iid=#{n_node[:iid]} has no begr (reference time)" unless n_ann
    end

    [failures, warnings]
  end
end
