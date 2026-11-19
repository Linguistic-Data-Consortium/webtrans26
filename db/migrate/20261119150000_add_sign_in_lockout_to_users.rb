# Failed sign-ins in a row, and the time a lock from too many of them ends
# (User#register_failed_sign_in).
class AddSignInLockoutToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :failed_sign_in_count, :integer, null: false, default: 0
    add_column :users, :locked_until, :datetime
  end
end
