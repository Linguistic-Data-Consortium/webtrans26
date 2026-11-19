# What the password policy needs to remember: when each user last chose a
# password (they must choose a new one once it's too old), and the digests of
# the ones they chose before (which may not be reused).
#
# password_changed_at starts empty for every existing user. No stored password
# can be checked against the new rules, so each user chooses a new one at their
# next sign-in.
class AddPasswordPolicyTracking < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :password_changed_at, :datetime

    create_table :password_histories do |t|
      t.references :user, null: false, index: true
      t.string :password_digest, null: false
      t.datetime :created_at, null: false
    end
  end
end
