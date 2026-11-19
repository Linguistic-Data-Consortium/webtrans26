# The digest of a password a user chose before, kept so it can't be chosen
# again (PasswordPolicy). User keeps the most recent User.password_history_count.
class PasswordHistory < ApplicationRecord
  belongs_to :user
end
