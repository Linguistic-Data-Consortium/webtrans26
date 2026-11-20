# The security audit log (SecurityEvent): who signed in, failed to, changed a
# password, was given a role, and so on. Rows are only ever added.
class CreateSecurityEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :security_events do |t|
      t.string :event, null: false
      t.integer :user_id   # whose account it concerns, when there is one
      t.integer :actor_id  # who did it, when that's someone else (an admin)
      t.string :ip
      t.string :user_agent
      t.json :details
      t.datetime :created_at, null: false
    end
    add_index :security_events, :created_at
    add_index :security_events, [ :user_id, :created_at ]
    add_index :security_events, [ :event, :created_at ]
  end
end
