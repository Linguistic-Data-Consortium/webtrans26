class CreateTaskDocids < ActiveRecord::Migration[8.1]
  # The list of documents a task hands to every one of its users.
  #
  # WorkflowTemp did this with three docids written into the class. A task
  # carrying the SameListForEveryone workflow reads its list from here instead,
  # so the list is data — entered on the Task tab, different per task, changed
  # without a deploy.
  #
  # One row per docid rather than a list in a column: "has this user already
  # had this one?" is then a query, the order is explicit, and a docid can
  # carry more later without a schema rethink.
  def change
    create_table :task_docids do |t|
      t.integer :task_id, null: false
      t.string :docid, null: false      # a kit's source_uid: s3://…, a path, whatever the task uses
      t.integer :position               # the order they're handed out in
      t.timestamps
      t.index [ :task_id, :position ]
      t.index [ :task_id, :docid ], unique: true
    end
  end
end
