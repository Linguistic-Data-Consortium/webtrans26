class AddUniqueIndexToGroupUsers < ActiveRecord::Migration[8.1]
  # group_users had no uniqueness constraint, so a user could be added to the
  # same group more than once. Drop any duplicates that already exist (keeping
  # the earliest row of each pair) before the index goes on. Rows with a null
  # group_id or user_id are left alone: they're invalid either way, and a
  # unique index treats nulls as distinct.
  def up
    execute <<~SQL
      DELETE FROM group_users
      WHERE group_id IS NOT NULL
        AND user_id IS NOT NULL
        AND id NOT IN (
          SELECT MIN(id) FROM group_users
          WHERE group_id IS NOT NULL AND user_id IS NOT NULL
          GROUP BY group_id, user_id
        )
    SQL
    add_index :group_users, [ :group_id, :user_id ], unique: true
  end

  def down
    remove_index :group_users, [ :group_id, :user_id ]
  end
end
