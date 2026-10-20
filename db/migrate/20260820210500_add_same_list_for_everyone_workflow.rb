class AddSameListForEveryoneWorkflow < ActiveRecord::Migration[8.1]
  # Create the workflow row. In a migration rather than db/seeds.rb for the
  # reason AddTempWorkflow gives: production's database already exists, so
  # bin/docker-entrypoint's db:prepare only runs migrations there and a new
  # seed line would never reach it.
  #
  # user_states must be set — tasks_controller#show calls
  # workflow.user_states.split(',') and blows up on nil.
  def up
    Workflow.where(name: "SameListForEveryone").first_or_create!(
      user_states: "needs_kit,has_kit",
      description: "every user works the same list of documents, entered on the task's Docid List tab"
    )
    # STI: the row loads as WorkflowSameListForEveryone, whose #main is what
    # Workflow#work falls through to for any name that isn't Orderly or
    # OnTheFly. Set with update_all so the migration never instantiates the
    # subclass itself.
    Workflow.where(name: "SameListForEveryone").update_all(type: "WorkflowSameListForEveryone")
  end

  def down
    # delete_all, not destroy_all: no instantiation, so this still works if the
    # class is gone by the time it's rolled back.
    Workflow.where(name: "SameListForEveryone").delete_all
  end
end
