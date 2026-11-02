# guides held per-user progress for the old jQuery tutorial, written through
# GuideChannel. The tutorial could no longer start and both are removed. The
# Svelte guides keep their state in localStorage. The columns are listed so
# that a rollback recreates the table, though not its rows.
class DropGuides < ActiveRecord::Migration[8.1]
  def change
    drop_table :guides do |t|
      t.boolean :active
      t.boolean :complete
      t.integer :currentstep
      t.boolean :dismissed
      t.integer :firststep
      t.string :misc
      t.string :name
      t.integer :nsteps
      t.datetime :updated_at
      t.integer :user_id
    end
  end
end
