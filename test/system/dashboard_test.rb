require "application_system_test_case"

class DashboardTest < ApplicationSystemTestCase
  # The dashboard page is a Svelte SPA-style shell — we need a real Vite build, not the stub
  # other tests use. Build once before the class runs; reset stub state between tests.
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

  teardown do
    ViteStub.enabled = true
  end

  test "signing in lands Alice on her dashboard which renders her task list" do
    visit new_session_url
    fill_in "email_address", with: users(:alice).email_address
    fill_in "password", with: "password123"
    click_on "Sign in"

    assert_current_path(/\/users\/\d+/)

    # The Svelte dashboard fetches /users/:id.json and renders the Tasks tab by default.
    # Wait for the user's task to appear in the Tasks table.
    assert_text projects(:alpha).name
    assert_text tasks(:alpha_task_one).name
  end

  test "dashboard shows all core tabs" do
    visit new_session_url
    fill_in "email_address", with: users(:alice).email_address
    fill_in "password", with: "password123"
    click_on "Sign in"

    assert_current_path(/\/users\/\d+/)

    # bits-ui Tabs render triggers as buttons with role="tab"
    %w[Work Projects Browse Workflows Groups Invites Permissions].each do |label|
      assert_selector "[role='tab']", text: /\A#{Regexp.escape(label)}\z/i, wait: 5
    end
  end

  test "clicking the Projects tab surfaces the current user's projects" do
    visit new_session_url
    fill_in "email_address", with: users(:alice).email_address
    fill_in "password", with: "password123"
    click_on "Sign in"

    assert_current_path(/\/users\/\d+/)
    assert_text tasks(:alpha_task_one).name # initial tasks tab loaded

    # Switch to Projects tab and expect to see the project name.
    find("[role='tab']", text: /Projects/i).click

    assert_text projects(:alpha).name
  end

  test "Work tab shows 'No Available Kits' when the task has no unassigned kits" do
    sign_in_browser users(:alice)

    # Alice is a task_user on alpha_task_one; fixtures have no kits → no kits available.
    within("table") do
      row = find("tr", text: tasks(:alpha_task_one).name)
      assert row.has_text?("No Available Kits"),
        "Action cell should read 'No Available Kits' when no unassigned kits exist"
    end
  end

  test "Work tab shows 'Start Now' once an unassigned kit exists for the task" do
    Kit.create!(
      task_id: tasks(:alpha_task_one).id,
      kit_type_id: tasks(:alpha_task_one).kit_type_id,
      state: "unassigned",
      uid: "work-tab-kit-#{SecureRandom.hex(3)}",
      tree_id: 1
    )

    sign_in_browser users(:alice)

    within("table") do
      row = find("tr", text: tasks(:alpha_task_one).name)
      assert row.has_link?("Start Now"), "Action cell should offer 'Start Now' when an unassigned kit exists"
    end
  end

  test "clicking the Task cell in the Work tab opens that task under the Projects tab" do
    sign_in_browser users(:alice)

    within("table") do
      find("td", text: /\A#{Regexp.escape(tasks(:alpha_task_one).name)}\z/).click
    end

    # goto(row, 'task') flips `tab` to 'projects' and opens the task with its sub-tabs.
    assert_selector "[role='tab']", text: /\ATask Info\z/i, wait: 5
    assert_selector "[role='tab']", text: /\ATask Members\z/i
  end

  # The Docid List tab is where a task's list of documents is entered — the one
  # the SameListForEveryone workflow gives to every user of the task.
  test "the Docid List tab saves a task's list and reads it back" do
    sign_in_browser users(:alice)

    within("table") do
      find("td", text: /\A#{Regexp.escape(tasks(:alpha_task_one).name)}\z/).click
    end
    assert_selector "[role='tab']", text: /\ATask Info\z/i, wait: 5
    find("[role='tab']", text: /\ADocid List\z/i).click

    assert_text "Documents for every user"
    # Orderly is the fixture's workflow, and it doesn't read the list.
    assert_text(/workflow is\s+Orderly/i)

    fill_in_docids = find("textarea")
    fill_in_docids.set("s3://bucket/one.json\n\ns3://bucket/two.json\n")
    click_on "Save list"

    assert_text "2 documents", wait: 5
    assert_equal [ "s3://bucket/one.json", "s3://bucket/two.json" ],
      tasks(:alpha_task_one).reload.docid_list
    assert_equal "s3://bucket/one.json\ns3://bucket/two.json", find("textarea").value,
      "the box shows the list as stored — the blank line is gone"
  end

  # The reported bug: a SameListForEveryone task has no kits until the user
  # arrives to be given them, so counting kit rows said "No Available Kits" and
  # never offered the link that would have made them.
  test "Work tab offers Start Now for a list task whose kits don't exist yet" do
    workflow = Workflow.where(name: "SameListForEveryone").first_or_create!(user_states: "needs_kit,has_kit")
    Workflow.where(id: workflow.id).update_all(type: "WorkflowSameListForEveryone")
    tasks(:alpha_task_one).update!(workflow: Workflow.find(workflow.id))
    TaskDocid.replace_for(tasks(:alpha_task_one).id, [ "s3://bucket/one.json", "s3://bucket/two.json" ])
    assert_equal 0, Kit.where(task_id: tasks(:alpha_task_one).id).count

    sign_in_browser users(:alice)

    within("table") do
      row = find("tr", text: tasks(:alpha_task_one).name)
      assert row.has_link?("Start Now"),
        "the list has documents alice hasn't had, so there is work to start"
      assert_equal "2 kits are left to be done", row.find("a", text: "Start Now")[:title]
    end
  end

  test "Work tab says No Available Kits once a list task's documents are all done" do
    workflow = Workflow.where(name: "SameListForEveryone").first_or_create!(user_states: "needs_kit,has_kit")
    Workflow.where(id: workflow.id).update_all(type: "WorkflowSameListForEveryone")
    task = tasks(:alpha_task_one)
    task.update!(workflow: Workflow.find(workflow.id))
    TaskDocid.replace_for(task.id, [ "s3://bucket/one.json" ])
    # Alice has already been given that document, and finished it.
    Kit.create!(
      task_id: task.id, kit_type_id: task.kit_type_id, user_id: users(:alice).id,
      source_uid: "s3://bucket/one.json", state: "done",
      uid: "list-kit-#{SecureRandom.hex(3)}", tree_id: 1
    )

    sign_in_browser users(:alice)

    within("table") do
      row = find("tr", text: task.name)
      assert row.has_text?("No Available Kits"), "the list is finished, and a list isn't a supply of work"
    end
  end

  # "Add Members from Task" on the Task Members tab: every member of the task
  # chosen is added to this one. alpha_task_two has no members in the fixtures;
  # alpha_task_one has alice and bob.
  test "the Task Members tab adds every member of another task" do
    sign_in_browser users(:alice)

    find("[role='tab']", text: /\AProjects\z/i, wait: 5).click
    within("table") { find("td", text: projects(:alpha).name).click }
    click_on "Open"
    find("[role='tab']", text: /Project Tasks/i, wait: 5).click
    within("table") { find("td", text: /\A#{Regexp.escape(tasks(:alpha_task_two).name)}\z/).click }
    click_on "Open"

    find("[role='tab']", text: /\ATask Members\z/i, wait: 5).click
    click_on "Add Members from Task"

    within("[role='dialog'][aria-modal='true']") do
      # The tasks alice administers, with their sizes — and not the one she's
      # looking at, which can't be copied into itself.
      assert_text(/#{Regexp.escape(tasks(:alpha_task_one).name)}.*2 members/, wait: 5)
      assert_no_selector "button", text: /#{Regexp.escape(tasks(:alpha_task_two).name)}/,
        wait: 1 # can't be copied into itself, so it isn't on the list

      find("button", text: /#{Regexp.escape(tasks(:alpha_task_one).name)}/).click
      # find(..., text:) rather than click_on: Capybara builds XPath from a
      # click_on locator, so a Regexp there matches nothing.
      find("button", text: /Add 2 from #{Regexp.escape(tasks(:alpha_task_one).name)}/).click
    end

    # Outside the `within`: the copy re-renders the dialog, which makes the
    # element that scope was anchored to stale. The summary stays up — the
    # members table refreshes when the dialog is closed, not before.
    assert_text(/2 added to #{Regexp.escape(tasks(:alpha_task_two).name)}/, wait: 5)
    assert_text(/added: .*#{Regexp.escape(users(:bob).name)}/)

    find("button", text: /\AClose\z/).click
    assert_text users(:bob).name, wait: 5

    assert_equal [ users(:alice).id, users(:bob).id ].sort,
      tasks(:alpha_task_two).reload.users.pluck(:id).sort
  end

  test "Work tab's Start Now link points at the workflow/work URL for the user's task" do
    # Full navigation + Svelte work-page load needs an AWS Cognito round-trip which we don't
    # want to stub in a system test. Instead: verify the link's href (which is what the click
    # would navigate to), and cover the full server-side assign_kit flow in the integration
    # test (test/integration/project_workflow_test.rb).
    Kit.create!(
      task_id: tasks(:alpha_task_one).id,
      kit_type_id: tasks(:alpha_task_one).kit_type_id,
      state: "unassigned",
      uid: "start-link-kit-#{SecureRandom.hex(3)}",
      tree_id: 1
    )

    sign_in_browser users(:alice)

    tu = task_users(:alice_admin_alpha_task_one)
    expected_href = "/workflows/#{tu.id}/work/#{tu.task.workflow_id}"

    within("table") do
      row = find("tr", text: tasks(:alpha_task_one).name)
      link = row.find("a", text: "Start Now")
      assert_equal expected_href, link["href"].sub(%r{\Ahttps?://[^/]+}, "")
    end
  end

  private

  def sign_in_browser(user, password: "password123")
    visit new_session_url
    fill_in "email_address", with: user.email_address
    fill_in "password", with: password
    click_on "Sign in"
    # See dashboard_crud_test: the redirect plus the dashboard's first paint can
    # exceed the default wait when the suite runs 8 browsers at once.
    assert_current_path(/\/users\/\d+/, wait: 10)
  end
end
