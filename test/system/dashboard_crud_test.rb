require "application_system_test_case"

# End-to-end tests that drive real user operations through the Svelte dashboard.
# The admin fixture is used because the "Create" / "Add Member" controls are gated on
# `lead_annotator?` which returns true for system admins via portal_manager?.
class DashboardCrudTest < ApplicationSystemTestCase
  class << self
    attr_accessor :vite_built
  end

  def self.ensure_vite_built!
    return if vite_built
    manifest = Rails.root.join("public/vite-test/.vite/manifest.json")
    unless manifest.exist?
      Bundler.with_unbundled_env do
        ok = system({ "RAILS_ENV" => "test" }, "bun", "run", "build", chdir: Rails.root.to_s)
        raise "vite build failed" unless ok
      end
    end
    self.vite_built = true
  end

  setup do
    self.class.ensure_vite_built!
    ViteStub.enabled = false
  end

  teardown { ViteStub.enabled = true }

  def sign_in_via_browser(user, password: "password123")
    visit new_session_url
    fill_in "email_address", with: user.email_address
    fill_in "password", with: password
    click_on "Sign in"
    # The sign-in POST, its redirect, and the dashboard's first paint all have to
    # land before this passes — give it more room than a plain assertion.
    assert_current_path(/\/users\/\d+/, wait: 10)
  end

  # The dashboard's key bindings (PageKeyControls) are only live once the Svelte
  # app has mounted, so a keystroke sent the moment <body> exists can be dropped.
  # Waiting for a rendered tab is the cheapest proof that mounting is done.
  def wait_for_dashboard
    find("[role='tab']", text: /\AProjects\z/i, wait: 10)
  end

  test "admin creates a new project from the Projects tab" do
    sign_in_via_browser users(:admin)

    # Wait for the dashboard to mount
    find("[role='tab']", text: /\AProjects\z/i, wait: 5).click

    # The "Create Project" dialog trigger appears for admins/lead annotators.
    click_on "Create Project"

    # Name input inside the dialog (bits-ui renders dialog content into a portal).
    # Scope to the modal dialog: the getting-started guide coachmark also uses
    # role="dialog" but is non-modal (no aria-modal), so match aria-modal to disambiguate.
    within("[role='dialog'][aria-modal='true']") do
      fill_in "dialog_create_name", with: "dashboard_made_project"
      click_on "Create"
    end

    # Wait until the Project row appears in the database (the create roundtrips to the server).
    assert_project_exists "dashboard_made_project"
  end

  test "admin creating a duplicate-named project shows an error toast and does not create" do
    existing = projects(:alpha)
    sign_in_via_browser users(:admin)

    find("[role='tab']", text: /\AProjects\z/i, wait: 5).click
    click_on "Create Project"

    within("[role='dialog'][aria-modal='true']") do
      fill_in "dialog_create_name", with: existing.name
      click_on "Create"
    end

    # Sonner renders the error toast; the duplicate project is rejected server-side.
    assert_text "has already been taken", wait: 5
    assert_equal 1, Project.where(name: existing.name).count
  end

  test "admin adds a user to an existing project via the Members tab" do
    sign_in_via_browser users(:admin)

    find("[role='tab']", text: /\AProjects\z/i, wait: 5).click

    # Select the alpha project row, then Open.
    within("table") { find("td", text: projects(:alpha).name).click }
    click_on "Open"

    find("[role='tab']", text: /Project Members/i, wait: 5).click
    click_on "Add Member"

    within("[role='dialog'][aria-modal='true']") do
      fill_in "dialog_create_member_name", with: users(:charlie).name
      # Match the suggestion button that contains the target user's exact name.
      find("button", text: /\A#{Regexp.escape(users(:charlie).name)}\z/, wait: 5).click
    end

    # The request should succeed; confirm server-side that Charlie is now a member.
    assert_member_of projects(:alpha), users(:charlie)
  end

  test "admin creates a task inside an existing project via the Project Tasks sub-tab" do
    sign_in_via_browser users(:admin)

    find("[role='tab']", text: /\AProjects\z/i, wait: 5).click
    within("table") { find("td", text: projects(:alpha).name).click }
    click_on "Open"

    find("[role='tab']", text: /Project Tasks/i, wait: 5).click
    click_on "Create Task"

    within("[role='dialog'][aria-modal='true']") do
      fill_in "dialog_create_name", with: "dashboard_made_task"
      click_on "Create"
    end

    assert_task_exists_on projects(:alpha), "dashboard_made_task"
  end

  test "admin deletes a project via the Projects tab" do
    target = Project.create!(name: "doomed_project")
    sign_in_via_browser users(:admin)

    find("[role='tab']", text: /\AProjects\z/i, wait: 5).click
    within("table") { find("td", text: target.name, wait: 5).click }
    click_on "Delete Project"

    within("[role='dialog'][aria-modal='true']") { click_on "Delete" }

    assert_project_destroyed target
  end

  test "admin removes a member from a project via the Project Members sub-tab" do
    sign_in_via_browser users(:admin)

    find("[role='tab']", text: /\AProjects\z/i, wait: 5).click
    within("table") { find("td", text: projects(:alpha).name).click }
    click_on "Open"

    find("[role='tab']", text: /Project Members/i, wait: 5).click
    # Select Bob's row in the Members table, then click Remove Member.
    within("table") { find("td", text: /\A#{Regexp.escape(users(:bob).name)}\z/, wait: 5).click }
    click_on "Remove Member"

    within("[role='dialog'][aria-modal='true']") { click_on "Delete" }

    assert_not_member_of projects(:alpha), users(:bob)
  end

  test "admin promotes a project member to admin via the Admin checkbox" do
    sign_in_via_browser users(:admin)

    find("[role='tab']", text: /\AProjects\z/i, wait: 5).click
    within("table") { find("td", text: projects(:alpha).name).click }
    click_on "Open"

    find("[role='tab']", text: /Project Members/i, wait: 5).click
    within("table") { find("td", text: /\A#{Regexp.escape(users(:bob).name)}\z/, wait: 5).click }

    # bits-ui renders checkboxes as <button role="checkbox">, not native <input type=checkbox>.
    # Find the Admin label and click the sibling checkbox it labels.
    label = find("label", text: /\AAdmin\z/, wait: 5)
    find("[role='checkbox'][aria-labelledby='#{label["id"]}']").click

    assert_project_user_admin projects(:alpha), users(:bob)
  end

  # ── Task sub-tabs ───────────────────────────────────────────────────────

  test "admin deletes a task from the Project Tasks sub-tab" do
    sign_in_via_browser users(:admin)
    target_name = tasks(:alpha_task_two).name

    find("[role='tab']", text: /\AProjects\z/i, wait: 5).click
    within("table") { find("td", text: projects(:alpha).name).click }
    click_on "Open"
    find("[role='tab']", text: /Project Tasks/i, wait: 5).click

    within("table") { find("td", text: /\A#{Regexp.escape(target_name)}\z/, wait: 5).click }
    click_on "Delete Task"
    within("[role='dialog'][aria-modal='true']") { click_on "Delete" }

    assert_task_destroyed projects(:alpha), target_name
  end

  test "admin adds a user to a task via Task Members" do
    sign_in_via_browser users(:admin)

    find("[role='tab']", text: /\AProjects\z/i, wait: 5).click
    within("table") { find("td", text: projects(:alpha).name).click }
    click_on "Open"
    find("[role='tab']", text: /Project Tasks/i, wait: 5).click

    within("table") { find("td", text: /\A#{Regexp.escape(tasks(:alpha_task_two).name)}\z/, wait: 5).click }
    click_on "Open Task Info"

    find("[role='tab']", text: /\ATask Members\z/i, wait: 5).click
    click_on "Add Member"

    within("[role='dialog'][aria-modal='true']") do
      fill_in "dialog_create_member_name", with: users(:charlie).name
      find("button", text: /\A#{Regexp.escape(users(:charlie).name)}\z/, wait: 5).click
    end

    assert_task_member tasks(:alpha_task_two), users(:charlie)
  end

  test "admin removes a user from a task via Task Members" do
    # Seed Charlie as a task_user on alpha_task_two so we have someone to remove.
    TaskUser.create!(task: tasks(:alpha_task_two), user: users(:charlie), state: "needs_kit")

    sign_in_via_browser users(:admin)

    find("[role='tab']", text: /\AProjects\z/i, wait: 5).click
    within("table") { find("td", text: projects(:alpha).name).click }
    click_on "Open"
    find("[role='tab']", text: /Project Tasks/i, wait: 5).click

    within("table") { find("td", text: /\A#{Regexp.escape(tasks(:alpha_task_two).name)}\z/, wait: 5).click }
    click_on "Open Task Info"

    find("[role='tab']", text: /\ATask Members\z/i, wait: 5).click
    within("table") { find("td", text: /\A#{Regexp.escape(users(:charlie).name)}\z/, wait: 5).click }
    click_on "Remove Member"
    within("[role='dialog'][aria-modal='true']") { click_on "Delete" }

    assert_not_task_member tasks(:alpha_task_two), users(:charlie)
  end

  test "admin promotes a task member to admin via the Admin checkbox" do
    sign_in_via_browser users(:admin)

    find("[role='tab']", text: /\AProjects\z/i, wait: 5).click
    within("table") { find("td", text: projects(:alpha).name).click }
    click_on "Open"
    find("[role='tab']", text: /Project Tasks/i, wait: 5).click

    within("table") { find("td", text: /\A#{Regexp.escape(tasks(:alpha_task_one).name)}\z/, wait: 5).click }
    click_on "Open Task Info"

    find("[role='tab']", text: /\ATask Members\z/i, wait: 5).click
    within("table") { find("td", text: /\A#{Regexp.escape(users(:bob).name)}\z/, wait: 5).click }

    label = find("label", text: /\AAdmin\z/, wait: 5)
    find("[role='checkbox'][aria-labelledby='#{label["id"]}']").click

    assert_task_user_admin tasks(:alpha_task_one), users(:bob)
  end

  test "admin creates kits on a task via the Create Kits (File Input) dialog" do
    sign_in_via_browser users(:admin)
    task = tasks(:alpha_task_two)

    find("[role='tab']", text: /\AProjects\z/i, wait: 5).click
    within("table") { find("td", text: projects(:alpha).name).click }
    click_on "Open"
    find("[role='tab']", text: /Project Tasks/i, wait: 5).click

    within("table") { find("td", text: /\A#{Regexp.escape(task.name)}\z/, wait: 5).click }
    click_on "Open Task Info"

    find("[role='tab']", text: /\AKits\z/i, wait: 5).click
    click_on "Create Kits (File Input)"

    # Write a tempfile containing docids (one per line) and attach it to the dialog's file input.
    file = Tempfile.new(["kits", ".txt"])
    file.write("file-doc-1\nfile-doc-2\nfile-doc-3\n")
    file.rewind
    file.close

    within("[role='dialog'][aria-modal='true']") do
      find("input[type='file']").set(file.path)
      click_on "upload"        # triggers FileReader.readAsText
      click_on "parse as text" # appears once text_upload is populated
      click_on "Create Kits"   # appears once json_upload is set
    end

    assert_kits_on task, source_uids: %w[file-doc-1 file-doc-2 file-doc-3]
  ensure
    file&.unlink
  end

  test "admin creates kits on a task via the Create Kits (Text Input) dialog" do
    sign_in_via_browser users(:admin)
    task = tasks(:alpha_task_two)

    find("[role='tab']", text: /\AProjects\z/i, wait: 5).click
    within("table") { find("td", text: projects(:alpha).name).click }
    click_on "Open"
    find("[role='tab']", text: /Project Tasks/i, wait: 5).click

    within("table") { find("td", text: /\A#{Regexp.escape(task.name)}\z/, wait: 5).click }
    click_on "Open Task Info"

    find("[role='tab']", text: /\AKits\z/i, wait: 5).click
    click_on "Create Kits (Text Input)"

    within("[role='dialog'][aria-modal='true']") do
      find("textarea").set("kit-docid-a\nkit-docid-b\n")
      click_on "parse as text"
      click_on "Create Kits"
    end

    assert_kits_on task, source_uids: %w[kit-docid-a kit-docid-b]
  end

  # ── Task Info inline editing ────────────────────────────────────────────

  test "admin renames a task via the debounced Name Patch input on Task Info" do
    sign_in_via_browser users(:admin)
    task = tasks(:alpha_task_two)
    new_name = "renamed_task_#{SecureRandom.hex(2)}"

    find("[role='tab']", text: /\AProjects\z/i, wait: 5).click
    within("table") { find("td", text: projects(:alpha).name).click }
    click_on "Open"
    find("[role='tab']", text: /Project Tasks/i, wait: 5).click

    within("table") { find("td", text: /\A#{Regexp.escape(task.name)}\z/, wait: 5).click }
    click_on "Open Task Info"

    # Task Info renders the Patch Name input (debounced 1s before it PATCHes).
    fill_in "Name", with: new_name
    assert_task_name_eventually task, new_name
  end

  # ── Kit Types tab ───────────────────────────────────────────────────────

  test "admin sees existing kit types listed on the Kit Types tab" do
    sign_in_via_browser users(:admin)

    find("[role='tab']", text: /\AKit Types\z/i, wait: 5).click

    within("table") { assert_text kit_types(:basic).name }
  end

  test "admin creates a kit type from the Kit Types tab" do
    sign_in_via_browser users(:admin)

    find("[role='tab']", text: /\AKit Types\z/i, wait: 5).click
    click_on "Create Kit Type"

    within("[role='dialog'][aria-modal='true']") do
      fill_in "dialog_create_name", with: "dashboard_made_kit_type"
      click_on "Create"
    end

    assert_kit_type_exists "dashboard_made_kit_type"
  end

  test "admin deletes a kit type from the Kit Types tab" do
    target = KitType.create!(name: "doomed_kit_type", node_class: node_classes(:root))
    sign_in_via_browser users(:admin)
    find("[role='tab']", text: /\AKit Types\z/i, wait: 5).click
    within("table") { find("td", text: /\A#{Regexp.escape(target.name)}\z/, wait: 5).click }
    click_on "Delete Kit Type"
    within("[role='dialog'][aria-modal='true']") { click_on "Delete" }
    assert_kit_type_destroyed target
  end

  # ── Project Info inline editing ─────────────────────────────────────────

  test "admin renames a project via the owner's Name Patch input on Project Info" do
    sign_in_via_browser users(:admin)
    project = projects(:alpha)
    new_name = "renamed_alpha_#{SecureRandom.hex(2)}"

    find("[role='tab']", text: /\AProjects\z/i, wait: 5).click
    within("table") { find("td", text: project.name).click }
    click_on "Open Project Info"

    fill_in "Name", with: new_name
    assert_project_name_eventually project, new_name
  end

  # ── Task Info select (Status) ───────────────────────────────────────────

  test "admin changes a task's Status via the Patch select on Task Info" do
    sign_in_via_browser users(:admin)
    task = tasks(:alpha_task_two)

    find("[role='tab']", text: /\AProjects\z/i, wait: 5).click
    within("table") { find("td", text: projects(:alpha).name).click }
    click_on "Open"
    find("[role='tab']", text: /Project Tasks/i, wait: 5).click

    within("table") { find("td", text: /\A#{Regexp.escape(task.name)}\z/, wait: 5).click }
    click_on "Open Task Info"

    # Status Patch renders a bits-ui Select. Select.Root is a wrapper (no DOM), so the label's
    # `for` points at nothing queryable. Instead, find the Status label and click the next
    # button sibling (the Select.Trigger).
    find(:xpath, "//label[normalize-space(text())='Status']/following-sibling::button[1]", wait: 5).click
    find("[role='option']", text: /\Ainactive\z/i, wait: 5).click

    assert_task_status_eventually task, "inactive"
  end

  test "admin changes a task's Workflow via the Patch select on Task Info" do
    sign_in_via_browser users(:admin)
    task = tasks(:alpha_task_two)

    find("[role='tab']", text: /\AProjects\z/i, wait: 5).click
    within("table") { find("td", text: projects(:alpha).name).click }
    click_on "Open"
    find("[role='tab']", text: /Project Tasks/i, wait: 5).click

    within("table") { find("td", text: /\A#{Regexp.escape(task.name)}\z/, wait: 5).click }
    click_on "Open Task Info"

    find(:xpath, "//label[normalize-space(text())='Workflow']/following-sibling::button[1]", wait: 5).click
    find("[role='option']", text: /\AOnTheFly\z/, wait: 5).click

    assert_task_workflow_eventually task, workflows(:on_the_fly)
  end

  test "admin changes a task's KitType via the Patch select on Task Info" do
    sign_in_via_browser users(:admin)
    task = tasks(:alpha_task_two)

    find("[role='tab']", text: /\AProjects\z/i, wait: 5).click
    within("table") { find("td", text: projects(:alpha).name).click }
    click_on "Open"
    find("[role='tab']", text: /Project Tasks/i, wait: 5).click

    within("table") { find("td", text: /\A#{Regexp.escape(task.name)}\z/, wait: 5).click }
    click_on "Open Task Info"

    find(:xpath, "//label[normalize-space(text())='KitType']/following-sibling::button[1]", wait: 5).click
    find("[role='option']", text: /\A#{Regexp.escape(kit_types(:advanced).name)}\z/, wait: 5).click

    assert_task_kit_type_eventually task, kit_types(:advanced)
  end

  test "admin changes a task_user's state via the Patch select on Task Members" do
    sign_in_via_browser users(:admin)

    find("[role='tab']", text: /\AProjects\z/i, wait: 5).click
    within("table") { find("td", text: projects(:alpha).name).click }
    click_on "Open"
    find("[role='tab']", text: /Project Tasks/i, wait: 5).click

    within("table") { find("td", text: /\A#{Regexp.escape(tasks(:alpha_task_one).name)}\z/, wait: 5).click }
    click_on "Open Task Info"

    find("[role='tab']", text: /\ATask Members\z/i, wait: 5).click
    within("table") { find("td", text: /\A#{Regexp.escape(users(:bob).name)}\z/, wait: 5).click }

    # The State Patch select appears on the right panel once a member is selected.
    find(:xpath, "//label[normalize-space(text())='State']/following-sibling::button[1]", wait: 5).click
    find("[role='option']", text: /\Ahold\z/, wait: 5).click

    assert_task_user_state_eventually tasks(:alpha_task_one), users(:bob), "hold"
  end

  # ── Groups tab ──────────────────────────────────────────────────────────

  test "admin creates a new group from the Groups tab" do
    sign_in_via_browser users(:admin)

    find("[role='tab']", text: /\AGroups\z/i, wait: 5).click
    click_on "Create Group"

    within("[role='dialog'][aria-modal='true']") do
      fill_in "dialog_create_name", with: "dashboard_made_group"
      click_on "Create"
    end

    assert_group_exists "dashboard_made_group"
  end

  test "admin deletes a group from the Groups tab" do
    target = Group.create!(name: "doomed_group")
    sign_in_via_browser users(:admin)

    find("[role='tab']", text: /\AGroups\z/i, wait: 5).click
    within("table") { find("td", text: /\A#{Regexp.escape(target.name)}\z/, wait: 5).click }
    click_on "Delete Group"
    within("[role='dialog'][aria-modal='true']") { click_on "Delete" }

    assert_group_destroyed target
  end

  # ── Features tab ────────────────────────────────────────────────────────

  test "admin creates a feature from the Features tab" do
    sign_in_via_browser users(:admin)

    find("[role='tab']", text: /\AFeatures\z/i, wait: 5).click
    click_on "Create Feature"

    within("[role='dialog'][aria-modal='true']") do
      fill_in "dialog_create_category", with: "task"
      fill_in "dialog_create_name", with: "dashboard_made_feature"
      click_on "Create"
    end

    assert_feature_exists category: "task", name: "dashboard_made_feature"
  end

  # ── Projects tab depth ──────────────────────────────────────────────────

  test "Projects table shows a Task Count column reflecting the project's tasks" do
    sign_in_via_browser users(:admin)

    find("[role='tab']", text: /\AProjects\z/i, wait: 5).click

    within("table") do
      row = find("tr", text: projects(:alpha).name, wait: 5)
      # alpha_task_one + alpha_task_two are fixtures under alpha
      assert_equal 2, projects(:alpha).tasks.count # sanity
      assert row.has_text?("2"), "Task Count cell for alpha should show 2"
    end
  end

  test "opening a task via 'Open Kit List' lands directly on the Kits sub-tab" do
    sign_in_via_browser users(:admin)

    find("[role='tab']", text: /\AProjects\z/i, wait: 5).click
    within("table") { find("td", text: projects(:alpha).name).click }
    click_on "Open"
    find("[role='tab']", text: /Project Tasks/i, wait: 5).click

    within("table") { find("td", text: /\A#{Regexp.escape(tasks(:alpha_task_one).name)}\z/, wait: 5).click }
    click_on "Open Kit List"

    # The Kits sub-tab is now active — its admin controls are present.
    assert_selector "button", text: "Create Kits (Text Input)", wait: 5
    assert_selector "button", text: "Create Kits (File Input)"
  end

  test "'Return to Project list' exits the opened project and restores the project table" do
    sign_in_via_browser users(:admin)

    find("[role='tab']", text: /\AProjects\z/i, wait: 5).click
    within("table") { find("td", text: projects(:alpha).name).click }
    click_on "Open"

    # Inside an open project — sub-tabs visible.
    assert_selector "[role='tab']", text: /\AProject Info\z/i, wait: 5

    click_on "Return to Project list"

    # Sub-tabs gone; we're back at the project list (the Create Project button is there).
    assert_no_selector "[role='tab']", text: /\AProject Info\z/i
    assert_selector "button", text: "Create Project"
    within("table") { assert_text projects(:alpha).name }
  end

  test "Kits sub-tab lists existing kits for the task" do
    kit = Kit.create!(
      task_id: tasks(:alpha_task_one).id,
      kit_type_id: tasks(:alpha_task_one).kit_type_id,
      state: "unassigned",
      uid: "existing-kit-#{SecureRandom.hex(3)}"
    )

    sign_in_via_browser users(:admin)

    find("[role='tab']", text: /\AProjects\z/i, wait: 5).click
    within("table") { find("td", text: projects(:alpha).name).click }
    click_on "Open"
    find("[role='tab']", text: /Project Tasks/i, wait: 5).click
    within("table") { find("td", text: /\A#{Regexp.escape(tasks(:alpha_task_one).name)}\z/, wait: 5).click }
    click_on "Open Kit List"

    # Wait for the kits table to render and assert the pre-seeded kit shows up.
    assert_text kit.uid, wait: 5
    assert_text "unassigned", wait: 5
  end

  test "a plain project member sees a read-only Project Info (no Name input, no Create Task, no Delete)" do
    # Alice is a plain member of beta_project (not owner, not admin — see fixtures).
    sign_in_via_browser users(:alice)

    find("[role='tab']", text: /\AProjects\z/i, wait: 5).click
    within("table") { find("td", text: projects(:beta).name).click }
    click_on "Open"

    # Project Info sub-tab visible but without the editable Name input or admin buttons.
    assert_selector "[role='tab']", text: /\AProject Info\z/i, wait: 5
    assert_no_field "Name"

    find("[role='tab']", text: /Project Tasks/i).click
    assert_no_selector "button", text: "Create Task"

    # Delete Project is only rendered for admins; ensure it's not present.
    assert_no_selector "button", text: "Delete Project"
  end

  # ── Workflows tab ───────────────────────────────────────────────────────

  test "admin sees existing workflows in the Workflows table" do
    sign_in_via_browser users(:admin)
    find("[role='tab']", text: /\AWorkflows\z/i, wait: 5).click

    within("table") do
      assert_text workflows(:orderly).name
      assert_text workflows(:on_the_fly).name
    end
  end

  test "admin creates a workflow from the Workflows tab" do
    sign_in_via_browser users(:admin)
    find("[role='tab']", text: /\AWorkflows\z/i, wait: 5).click
    click_on "Create Workflow"

    within("[role='dialog'][aria-modal='true']") do
      fill_in "dialog_create_name", with: "DashboardWorkflow"
      click_on "Create"
    end

    assert_workflow_exists "DashboardWorkflow"
  end

  test "non-admin does not see Create Workflow button" do
    sign_in_via_browser users(:alice)
    find("[role='tab']", text: /\AWorkflows\z/i, wait: 5).click
    assert_no_selector "button", text: "Create Workflow"
  end

  # ── Browse tab ──────────────────────────────────────────────────────────

  test "Browse tab shows the 'deactivated' placeholder" do
    sign_in_via_browser users(:admin)
    find("[role='tab']", text: /\ABrowse\z/i, wait: 5).click
    assert_text "deactivated"
  end

  # ── Kit Types: namespace select + permission gating ─────────────────────

  test "admin changes the Namespace of a kit type via the Patch select" do
    # The Namespace dropdown is populated from `NodeClass.sorted_root_nodes`. Seed a second
    # NodeClass parented to Root so there are two distinct options to switch between.
    other = NodeClass.create!(name: "AnotherClass:Root", parent: node_classes(:root))

    sign_in_via_browser users(:admin)
    find("[role='tab']", text: /\AKit Types\z/i, wait: 5).click
    within("table") { find("td", text: /\A#{Regexp.escape(kit_types(:basic).name)}\z/, wait: 5).click }
    click_on "Open"

    find(:xpath, "//label[normalize-space(text())='Namespace']/following-sibling::button[1]", wait: 5).click
    find("[role='option']", text: /\AAnotherClass\z/, wait: 5).click

    assert_kit_type_node_class_eventually kit_types(:basic), other
  end

  test "non-admin does not see Create Kit Type button" do
    sign_in_via_browser users(:alice)
    find("[role='tab']", text: /\AKit Types\z/i, wait: 5).click
    assert_no_selector "button", text: "Create Kit Type"
  end

  # ── Features: list + permission gating ──────────────────────────────────

  test "admin sees existing features in the Features table" do
    f1 = Feature.create!(category: "task", name: "list_test_a", value: "v1", label: "Lbl A", description: "Desc A")
    f2 = Feature.create!(category: "kit_type", name: "list_test_b", value: "v2", label: "Lbl B", description: "Desc B")

    sign_in_via_browser users(:admin)
    find("[role='tab']", text: /\AFeatures\z/i, wait: 5).click

    within("table") do
      assert_text f1.name
      assert_text f2.name
      assert_text f1.label
      assert_text f2.label
    end
  end

  test "non-admin does not see Create Feature button" do
    sign_in_via_browser users(:alice)
    find("[role='tab']", text: /\AFeatures\z/i, wait: 5).click
    assert_no_selector "button", text: "Create Feature"
  end

  # ── Groups: list + permission gating ────────────────────────────────────

  test "admin sees existing groups in the Groups table" do
    sign_in_via_browser users(:admin)
    find("[role='tab']", text: /\AGroups\z/i, wait: 5).click

    within("table") do
      assert_text groups(:researchers).name
      assert_text groups(:portal_managers).name
      assert_text groups(:project_managers).name
    end
  end

  test "non-admin does not see Create Group button" do
    sign_in_via_browser users(:alice)
    find("[role='tab']", text: /\AGroups\z/i, wait: 5).click
    assert_no_selector "button", text: "Create Group"
  end

  # ── Invites: table columns + pending invite display ─────────────────────

  test "admin sees the Invites table column headers" do
    sign_in_via_browser users(:admin)
    find("[role='tab']", text: /\AInvites\z/i, wait: 5).click
    assert_text "Email"
    assert_text "Sent"
    assert_text "Activated"
  end

  test "admin sees pending invites they have sent in the Invites table" do
    pending = User.new(email_address: "invitee_#{SecureRandom.hex(3)}@example.com", password: User.new_token)
    pending.save(validate: false)
    pending.create_invite_digest(users(:admin).id)

    sign_in_via_browser users(:admin)
    find("[role='tab']", text: /\AInvites\z/i, wait: 5).click

    within("table") { assert_text pending.email_address }
  end

  # ── Project Members: Owner flag ─────────────────────────────────────────

  test "admin transfers ownership by toggling the Owner checkbox on a project member" do
    sign_in_via_browser users(:admin)

    find("[role='tab']", text: /\AProjects\z/i, wait: 5).click
    within("table") { find("td", text: projects(:alpha).name).click }
    click_on "Open"

    find("[role='tab']", text: /Project Members/i, wait: 5).click
    within("table") { find("td", text: /\A#{Regexp.escape(users(:bob).name)}\z/, wait: 5).click }

    # Click the Owner checkbox via the label-id / aria-labelledby hop.
    label = find("label", text: /\AOwner\z/, wait: 5)
    find("[role='checkbox'][aria-labelledby='#{label["id"]}']").click

    assert_project_user_owner projects(:alpha), users(:bob)
  end

  # ── Features: open + rename + edit category/value/label ─────────────────

  test "admin opens a feature and edits its fields" do
    target = Feature.create!(category: "task", name: "editable_feature", value: "x", label: "label x")
    sign_in_via_browser users(:admin)

    find("[role='tab']", text: /\AFeatures\z/i, wait: 5).click
    within("table") { find("td", text: /\A#{Regexp.escape(target.name)}\z/, wait: 5).click }
    click_on "Open"

    # All 4 editable Patch inputs are present on the Feature detail view.
    assert_selector "label", text: /\ACategory\z/, wait: 5
    assert_selector "label", text: /\AName\z/
    assert_selector "label", text: /\AValue\z/
    assert_selector "label", text: /\ALabel\z/

    fill_in "Name", with: "edited_feature_name"
    assert_feature_name_eventually target, "edited_feature_name"

    fill_in "Value", with: "new_value"
    assert_feature_value_eventually target, "new_value"
  end

  test "admin edits a feature's Category and Description via Patch inputs" do
    target = Feature.create!(category: "task", name: "cat_test_feature", value: "v", label: "l", description: "short")
    sign_in_via_browser users(:admin)

    find("[role='tab']", text: /\AFeatures\z/i, wait: 5).click
    within("table") { find("td", text: /\A#{Regexp.escape(target.name)}\z/, wait: 5).click }
    click_on "Open"

    fill_in "Category", with: "kit_type"
    assert_feature_category_eventually target, "kit_type"

    fill_in "Description", with: "a longer description"
    assert_feature_description_eventually target, "a longer description"
  end

  # ── Permissions: client-side role toggle ─────────────────────────────────

  test "admin cycles through roles on the Permissions tab (client-side only)" do
    sign_in_via_browser users(:admin)

    find("[role='tab']", text: /\APermissions\z/i, wait: 5).click

    # The role buttons mutate client-side $state only — they do not hit the server.
    assert_text "You're an Admin"
    click_on "Set yourself to Portal Manager"
    assert_text "You're a Portal Manager"

    click_on "Set yourself to Project Manager"
    assert_text "You're a Project Manager"

    click_on "Set yourself to normal User"
    assert_text "You don't have any global permissions"
  end

  # ── Permissions: Resend Email ───────────────────────────────────────────

  # ── Kit Types open + rename ─────────────────────────────────────────────

  test "admin opens a kit type and renames it via the Name Patch input" do
    sign_in_via_browser users(:admin)
    kit_type = kit_types(:basic)
    new_name = "renamed_kit_type_#{SecureRandom.hex(2)}"

    find("[role='tab']", text: /\AKit Types\z/i, wait: 5).click
    within("table") { find("td", text: /\A#{Regexp.escape(kit_type.name)}\z/, wait: 5).click }
    click_on "Open"

    assert_selector "label", text: /\AName\z/, wait: 5
    fill_in "Name", with: new_name

    assert_kit_type_name_eventually kit_type, new_name
  end

  # ── Groups open, rename, member add/remove ──────────────────────────────

  test "admin opens a group and sees Group Info + Group Members sub-tabs" do
    sign_in_via_browser users(:admin)

    find("[role='tab']", text: /\AGroups\z/i, wait: 5).click
    within("table") { find("td", text: /\A#{Regexp.escape(groups(:researchers).name)}\z/, wait: 5).click }
    click_on "Open"

    assert_selector "[role='tab']", text: /\AGroup Info\z/i, wait: 5
    assert_selector "[role='tab']", text: /\AGroup Members\z/i
  end

  test "admin renames a group via the Name Patch input on Group Info" do
    sign_in_via_browser users(:admin)
    group = groups(:researchers)
    new_name = "renamed_group_#{SecureRandom.hex(2)}"

    find("[role='tab']", text: /\AGroups\z/i, wait: 5).click
    within("table") { find("td", text: /\A#{Regexp.escape(group.name)}\z/, wait: 5).click }
    click_on "Open"

    fill_in "Name", with: new_name
    assert_group_name_eventually group, new_name
  end

  test "admin adds a user to a group via Group Members" do
    sign_in_via_browser users(:admin)

    find("[role='tab']", text: /\AGroups\z/i, wait: 5).click
    within("table") { find("td", text: /\A#{Regexp.escape(groups(:researchers).name)}\z/, wait: 5).click }
    click_on "Open"
    find("[role='tab']", text: /\AGroup Members\z/i, wait: 5).click

    click_on "Add Member"
    within("[role='dialog'][aria-modal='true']") do
      fill_in "dialog_create_member_name", with: users(:charlie).name
      find("button", text: /\A#{Regexp.escape(users(:charlie).name)}\z/, wait: 5).click
    end

    assert_group_member groups(:researchers), users(:charlie)
  end

  test "admin removes a user from a group via Group Members" do
    sign_in_via_browser users(:admin)
    # Bob is pre-seeded into researchers via fixture group_users.yml

    find("[role='tab']", text: /\AGroups\z/i, wait: 5).click
    within("table") { find("td", text: /\A#{Regexp.escape(groups(:researchers).name)}\z/, wait: 5).click }
    click_on "Open"
    find("[role='tab']", text: /\AGroup Members\z/i, wait: 5).click

    within("table") { find("td", text: /\A#{Regexp.escape(users(:bob).name)}\z/, wait: 5).click }
    click_on "Remove Member"
    within("[role='dialog'][aria-modal='true']") { click_on "Delete" }

    assert_not_group_member groups(:researchers), users(:bob)
  end

  # ── Features list + delete ──────────────────────────────────────────────

  test "admin deletes a feature from the Features tab" do
    target = Feature.create!(category: "task", name: "doomed_feature")
    sign_in_via_browser users(:admin)

    find("[role='tab']", text: /\AFeatures\z/i, wait: 5).click
    within("table") { find("td", text: /\A#{Regexp.escape(target.name)}\z/, wait: 5).click }
    click_on "Delete Feature"
    within("[role='dialog'][aria-modal='true']") { click_on "Delete" }

    assert_feature_destroyed target
  end

  # ── Invites tab ─────────────────────────────────────────────────────────

  test "admin sees the invites table on the Invites tab" do
    sign_in_via_browser users(:admin)

    find("[role='tab']", text: /\AInvites\z/i, wait: 5).click

    assert_text "Invitations you made"
  end

  # ── Permissions tab ─────────────────────────────────────────────────────

  test "admin sees their role on the Permissions tab" do
    sign_in_via_browser users(:admin)

    find("[role='tab']", text: /\APermissions\z/i, wait: 5).click

    assert_text "You're an Admin"
    assert_selector "button", text: "Set yourself to Portal Manager"
  end

  # ── Admin-only jump-to-readonly input ───────────────────────────────────

  test "admin can open the jump-to-readonly popup with `j`; non-admin cannot" do
    sign_in_via_browser users(:admin)
    wait_for_dashboard # the `j` binding only exists once the app has mounted

    # Admin: pressing `j` opens the popup.
    find("body").send_keys("j")
    assert_selector "dialog[open]", text: "Jump to readonly"
    # Close it before signing out.
    find("body").send_keys(:escape)

    # See note in login_test.rb — the visible "Sign out" button no longer exists.
    page.execute_script("document.querySelector('#newsignout form').submit()")
    sign_in_via_browser users(:alice)
    wait_for_dashboard

    # Non-admin: pressing `j` does nothing.
    find("body").send_keys("j")
    assert_no_selector "dialog[open]"
  end

  private

  def assert_project_exists(name, timeout: 5)
    deadline = Time.now + timeout
    while Time.now < deadline
      return if Project.exists?(name: name)
      sleep 0.1
    end
    flunk "project #{name.inspect} was not created within #{timeout}s"
  end

  def assert_project_destroyed(project, timeout: 5)
    deadline = Time.now + timeout
    while Time.now < deadline
      return unless Project.exists?(project.id)
      sleep 0.1
    end
    flunk "project #{project.name} was not deleted within #{timeout}s"
  end

  def assert_task_exists_on(project, name, timeout: 5)
    deadline = Time.now + timeout
    while Time.now < deadline
      return if project.tasks.exists?(name: name)
      sleep 0.1
    end
    flunk "task #{name.inspect} was not created on #{project.name} within #{timeout}s"
  end

  def assert_member_of(project, user, timeout: 5)
    deadline = Time.now + timeout
    while Time.now < deadline
      return if project.reload.users.include?(user)
      sleep 0.1
    end
    flunk "#{user.name} was not added to project #{project.name} within #{timeout}s"
  end

  def assert_not_member_of(project, user, timeout: 5)
    deadline = Time.now + timeout
    while Time.now < deadline
      return unless project.reload.users.include?(user)
      sleep 0.1
    end
    flunk "#{user.name} was not removed from project #{project.name} within #{timeout}s"
  end

  def assert_project_user_admin(project, user, timeout: 5)
    deadline = Time.now + timeout
    while Time.now < deadline
      pu = project.project_users.find_by(user_id: user.id)
      return if pu && pu.admin?
      sleep 0.1
    end
    flunk "#{user.name} was not promoted to admin on #{project.name} within #{timeout}s"
  end

  def assert_task_destroyed(project, name, timeout: 5)
    deadline = Time.now + timeout
    while Time.now < deadline
      return unless project.tasks.exists?(name: name)
      sleep 0.1
    end
    flunk "task #{name.inspect} was not deleted from #{project.name} within #{timeout}s"
  end

  def assert_task_member(task, user, timeout: 5)
    deadline = Time.now + timeout
    while Time.now < deadline
      return if task.reload.users.include?(user)
      sleep 0.1
    end
    flunk "#{user.name} was not added to task #{task.name} within #{timeout}s"
  end

  def assert_not_task_member(task, user, timeout: 5)
    deadline = Time.now + timeout
    while Time.now < deadline
      return unless task.reload.users.include?(user)
      sleep 0.1
    end
    flunk "#{user.name} was not removed from task #{task.name} within #{timeout}s"
  end

  def assert_task_user_admin(task, user, timeout: 5)
    deadline = Time.now + timeout
    while Time.now < deadline
      tu = task.task_users.find_by(user_id: user.id)
      return if tu && tu.admin?
      sleep 0.1
    end
    flunk "#{user.name} was not promoted to admin on task #{task.name} within #{timeout}s"
  end

  def assert_kits_on(task, source_uids:, timeout: 10)
    deadline = Time.now + timeout
    expected = source_uids.sort
    while Time.now < deadline
      found = task.kits.pluck(:source_uid).compact.sort & expected
      return if found == expected
      sleep 0.1
    end
    actual = task.kits.pluck(:source_uid).compact
    flunk "expected kits with source_uids #{expected.inspect} on #{task.name}; found #{actual.inspect}"
  end

  def assert_task_name_eventually(task, new_name, timeout: 6)
    # The Patch input waits ~1s after the last keystroke before firing the PATCH.
    deadline = Time.now + timeout
    while Time.now < deadline
      return if task.reload.name == new_name
      sleep 0.1
    end
    flunk "task #{task.id} was not renamed to #{new_name.inspect} within #{timeout}s (current: #{task.reload.name.inspect})"
  end

  def assert_kit_type_exists(name, timeout: 5)
    deadline = Time.now + timeout
    while Time.now < deadline
      return if KitType.exists?(name: name)
      sleep 0.1
    end
    flunk "kit_type #{name.inspect} was not created within #{timeout}s"
  end

  def assert_kit_type_destroyed(kit_type, timeout: 5)
    deadline = Time.now + timeout
    while Time.now < deadline
      return unless KitType.exists?(kit_type.id)
      sleep 0.1
    end
    flunk "kit_type #{kit_type.name} was not deleted within #{timeout}s"
  end

  def assert_project_name_eventually(project, new_name, timeout: 6)
    deadline = Time.now + timeout
    while Time.now < deadline
      return if project.reload.name == new_name
      sleep 0.1
    end
    flunk "project #{project.id} was not renamed to #{new_name.inspect} within #{timeout}s"
  end

  def assert_task_status_eventually(task, status, timeout: 5)
    deadline = Time.now + timeout
    while Time.now < deadline
      return if task.reload.status == status
      sleep 0.1
    end
    flunk "task #{task.id} status did not change to #{status.inspect} within #{timeout}s (current: #{task.reload.status.inspect})"
  end

  def assert_group_exists(name, timeout: 5)
    deadline = Time.now + timeout
    while Time.now < deadline
      return if Group.exists?(name: name)
      sleep 0.1
    end
    flunk "group #{name.inspect} was not created within #{timeout}s"
  end

  def assert_group_destroyed(group, timeout: 5)
    deadline = Time.now + timeout
    while Time.now < deadline
      return unless Group.exists?(group.id)
      sleep 0.1
    end
    flunk "group #{group.name} was not deleted within #{timeout}s"
  end

  def assert_feature_exists(category:, name:, timeout: 5)
    deadline = Time.now + timeout
    while Time.now < deadline
      return if Feature.exists?(category: category, name: name)
      sleep 0.1
    end
    flunk "feature #{category}/#{name} was not created within #{timeout}s"
  end

  def assert_task_workflow_eventually(task, workflow, timeout: 5)
    deadline = Time.now + timeout
    while Time.now < deadline
      return if task.reload.workflow_id == workflow.id
      sleep 0.1
    end
    flunk "task #{task.id} workflow_id did not change to #{workflow.name.inspect} within #{timeout}s"
  end

  def assert_task_kit_type_eventually(task, kit_type, timeout: 5)
    deadline = Time.now + timeout
    while Time.now < deadline
      return if task.reload.kit_type_id == kit_type.id
      sleep 0.1
    end
    flunk "task #{task.id} kit_type_id did not change to #{kit_type.name.inspect} within #{timeout}s"
  end

  def assert_task_user_state_eventually(task, user, state, timeout: 5)
    deadline = Time.now + timeout
    while Time.now < deadline
      tu = task.task_users.find_by(user_id: user.id)
      return if tu && tu.state == state
      sleep 0.1
    end
    flunk "#{user.name}'s state on task #{task.name} did not change to #{state.inspect} within #{timeout}s"
  end

  def assert_kit_type_name_eventually(kit_type, new_name, timeout: 6)
    deadline = Time.now + timeout
    while Time.now < deadline
      return if kit_type.reload.name == new_name
      sleep 0.1
    end
    flunk "kit_type #{kit_type.id} was not renamed to #{new_name.inspect} within #{timeout}s"
  end

  def assert_group_name_eventually(group, new_name, timeout: 6)
    deadline = Time.now + timeout
    while Time.now < deadline
      return if group.reload.name == new_name
      sleep 0.1
    end
    flunk "group #{group.id} was not renamed to #{new_name.inspect} within #{timeout}s"
  end

  def assert_group_member(group, user, timeout: 5)
    deadline = Time.now + timeout
    while Time.now < deadline
      return if group.reload.users.include?(user)
      sleep 0.1
    end
    flunk "#{user.name} was not added to group #{group.name} within #{timeout}s"
  end

  def assert_not_group_member(group, user, timeout: 5)
    deadline = Time.now + timeout
    while Time.now < deadline
      return unless group.reload.users.include?(user)
      sleep 0.1
    end
    flunk "#{user.name} was not removed from group #{group.name} within #{timeout}s"
  end

  def assert_feature_destroyed(feature, timeout: 5)
    deadline = Time.now + timeout
    while Time.now < deadline
      return unless Feature.exists?(feature.id)
      sleep 0.1
    end
    flunk "feature #{feature.name} was not deleted within #{timeout}s"
  end

  def assert_project_user_owner(project, user, timeout: 5)
    deadline = Time.now + timeout
    while Time.now < deadline
      pu = project.project_users.find_by(user_id: user.id)
      return if pu && pu.owner?
      sleep 0.1
    end
    flunk "#{user.name} was not made owner of #{project.name} within #{timeout}s"
  end

  def assert_feature_name_eventually(feature, new_name, timeout: 6)
    deadline = Time.now + timeout
    while Time.now < deadline
      return if feature.reload.name == new_name
      sleep 0.1
    end
    flunk "feature #{feature.id} was not renamed to #{new_name.inspect} within #{timeout}s"
  end

  def assert_feature_value_eventually(feature, new_value, timeout: 6)
    deadline = Time.now + timeout
    while Time.now < deadline
      return if feature.reload.value == new_value
      sleep 0.1
    end
    flunk "feature #{feature.id}.value did not change to #{new_value.inspect} within #{timeout}s"
  end

  def assert_feature_category_eventually(feature, new_category, timeout: 6)
    deadline = Time.now + timeout
    while Time.now < deadline
      return if feature.reload.category == new_category
      sleep 0.1
    end
    flunk "feature #{feature.id}.category did not change to #{new_category.inspect} within #{timeout}s"
  end

  def assert_feature_description_eventually(feature, new_description, timeout: 6)
    deadline = Time.now + timeout
    while Time.now < deadline
      return if feature.reload.description == new_description
      sleep 0.1
    end
    flunk "feature #{feature.id}.description did not change to #{new_description.inspect} within #{timeout}s"
  end

  def assert_kit_type_node_class_eventually(kit_type, node_class, timeout: 5)
    deadline = Time.now + timeout
    while Time.now < deadline
      return if kit_type.reload.node_class_id == node_class.id
      sleep 0.1
    end
    flunk "kit_type #{kit_type.id}.node_class_id did not change to #{node_class.id} within #{timeout}s"
  end

  def assert_workflow_exists(name, timeout: 5)
    deadline = Time.now + timeout
    while Time.now < deadline
      return if Workflow.exists?(name: name)
      sleep 0.1
    end
    flunk "workflow #{name.inspect} was not created within #{timeout}s"
  end
end
