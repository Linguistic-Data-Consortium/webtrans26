class AddAccessLinkToUsers < ActiveRecord::Migration[8.1]
  # One-time sign-in links (AccessLinksController). Separate from the
  # invite_* columns so a minted link never collides with the email-invite
  # flow: access_digest is the hashed token, and clearing it is what makes a
  # link single-use.
  def change
    add_column :users, :access_digest, :string
    add_column :users, :access_created_at, :datetime
    add_column :users, :access_created_by, :integer
  end
end
