# The rules a password must meet whenever someone chooses one:
#
#   - at least MIN_LENGTH characters;
#   - an uppercase letter, a lowercase letter, a number and a special character;
#   - no common word or phrase (config/password_blocklist.txt), even with
#     letters swapped for look-alike digits and symbols;
#   - nothing from the account itself: the username or the email address;
#   - not the current password nor any earlier one (PasswordHistory; all of
#     them unless PASSWORD_HISTORY limits it to the last N).
#
# User validates with it; a password the app generates itself is exempt (see
# User#assign_generated_password). How often a password must be changed is
# User#password_expired?.
class PasswordPolicy
  MIN_LENGTH = 16

  # Undo the substitutions people make to dress up a word.
  LOOKALIKES = { "0" => "o", "1" => "i", "!" => "i", "3" => "e", "4" => "a", "@" => "a",
                 "5" => "s", "$" => "s", "7" => "t", "+" => "t", "8" => "b", "9" => "g" }.freeze

  def self.blocklist
    @blocklist ||= Rails.root.join("config/password_blocklist.txt").readlines
      .map { |line| line.sub(/#.*/, "").strip.downcase }
      .reject { |word| word.length < 4 }
      .uniq.freeze
  end

  # Every reason +password+ fails the policy for +user+, as sentences to show.
  def self.errors_for(password, user)
    new(password, user).errors
  end

  def initialize(password, user)
    @password = password.to_s
    @user = user
  end

  def errors
    errors = []
    errors << "must be at least #{MIN_LENGTH} characters" if @password.length < MIN_LENGTH
    missing = missing_kinds
    errors << "must include #{missing.to_sentence}" if missing.any?
    if (word = common_word)
      errors << "must not contain a common word or pattern (\"#{word}\")"
    end
    errors << "must not contain your username or email address" if contains_account_details?
    errors << "must not be one you've used before" if used_before?
    errors
  end

  private

  def missing_kinds
    {
      "an uppercase letter" => /\p{Lu}/,
      "a lowercase letter" => /\p{Ll}/,
      "a number" => /\d/,
      "a special character" => /[^\p{L}\p{N}]/
    }.reject { |_, pattern| @password.match?(pattern) }.keys
  end

  # The password as letters only, read both literally and with look-alikes
  # undone ("P@ssw0rd!" -> "password"). "1" can stand for i or l, so both.
  def readings
    @readings ||= begin
      lower = @password.downcase
      plain = lower.gsub(/[^\p{L}\p{N}]/, "")
      swapped = lower.chars.map { |c| LOOKALIKES.fetch(c, c) }.join.gsub(/[^\p{L}\p{N}]/, "")
      [ plain, swapped, swapped.tr("i", "l") ].uniq
    end
  end

  def common_word
    self.class.blocklist.find { |word| readings.any? { |r| r.include?(word) } }
  end

  # The username, the email address and the parts of each long enough to mean
  # something (three characters or more): "jane.doe@lab.org" gives jane, doe,
  # janedoe and lab.
  def account_details
    return [] unless @user
    name = @user.name.to_s.downcase
    local, domain = @user.email_address.to_s.downcase.split("@", 2)
    parts = [ name, local, *name.split(/[^\p{L}\p{N}]+/), *local.to_s.split(/[^\p{L}\p{N}]+/),
              domain.to_s.split(".").first ]
    parts.compact.map { |p| p.gsub(/[^\p{L}\p{N}]/, "") }.select { |p| p.length >= 3 }.uniq
  end

  def contains_account_details?
    account_details.any? { |detail| readings.any? { |r| r.include?(detail) } }
  end

  def used_before?
    return false unless @user&.persisted?
    digests = @user.password_histories.limit(User.password_history_count).pluck(:password_digest)
    digests << @user.password_digest_in_database
    digests.compact.uniq.any? { |digest| BCrypt::Password.new(digest).is_password?(@password) }
  end
end
