require "test_helper"

class UserTest < ActiveSupport::TestCase
  def valid_user_attrs(overrides = {})
    {
      name: "newuser",
      email_address: "new@example.com",
      password: GOOD_PASSWORD,
      password_confirmation: GOOD_PASSWORD
    }.merge(overrides)
  end

  test "fixture users are valid" do
    assert users(:alice).valid?
    assert users(:admin).valid?
    assert users(:unactivated).valid?
  end

  test "requires name" do
    user = User.new(valid_user_attrs(name: ""))
    assert_not user.valid?
    assert user.errors[:name].any?
  end

  test "rejects invalid name formats" do
    ["has spaces", "bad!chars", "slash/name", "コーヒー"].each do |bad|
      user = User.new(valid_user_attrs(name: bad))
      assert_not user.valid?, "expected #{bad.inspect} to be invalid"
    end
  end

  test "accepts allowed name characters" do
    ["good_name", "good-name", "good.name", "abc123"].each do |ok|
      user = User.new(valid_user_attrs(name: ok, email_address: "#{ok}@example.com"))
      assert user.valid?, "expected #{ok.inspect} valid: #{user.errors.full_messages}"
    end
  end

  test "requires unique name case-insensitively" do
    user = User.new(valid_user_attrs(name: users(:alice).name.upcase, email_address: "x@example.com"))
    assert_not user.valid?
    assert user.errors[:name].any?
  end

  test "requires valid email" do
    ["no-at-sign", "foo@", "@bar.com", "foo@bar"].each do |bad|
      user = User.new(valid_user_attrs(email_address: bad))
      assert_not user.valid?, "expected #{bad.inspect} to be invalid"
    end
  end

  test "normalizes email to lowercase and strips whitespace" do
    user = User.create!(valid_user_attrs(email_address: "  MIXED@Example.COM  "))
    assert_equal "mixed@example.com", user.email_address
  end

  test "requires unique email case-insensitively" do
    user = User.new(valid_user_attrs(email_address: users(:alice).email_address.upcase))
    assert_not user.valid?
    assert user.errors[:email_address].any?
  end

  # ── password policy ──────────────────────────────────────────────────────

  def password_errors(password, attrs = {})
    user = User.new(valid_user_attrs(attrs.merge(password: password, password_confirmation: password)))
    user.valid?
    user.errors[:password]
  end

  test "a password meeting every rule is accepted" do
    assert_empty password_errors(GOOD_PASSWORD)
  end

  test "a password needs at least 16 characters" do
    assert_includes password_errors("Sh0rt^Glacier"), "must be at least 16 characters"
  end

  test "a password needs upper and lower case, a number and a special character" do
    assert_includes password_errors("tromboneglaciermild"),
      "must include an uppercase letter, a number, and a special character"
    assert_empty password_errors("Trombone-Glacier-Mild9")
  end

  test "a password can't contain a common word, even dressed up" do
    assert_includes password_errors("Glacier#P@ssw0rd-Mild"), %(must not contain a common word or pattern ("password"))
    assert_includes password_errors("Glacier#Qwerty7-Mildly"), %(must not contain a common word or pattern ("qwerty"))
    assert_includes password_errors("Glacier#Mild-12345678"), %(must not contain a common word or pattern ("1234"))
  end

  test "a password can't contain the username or any part of the email address" do
    msg = "must not contain your username or email address"
    assert_includes password_errors("Newuser#Glacier9Mild"), msg
    assert_includes password_errors("Glacier#Mild9Example", email_address: "jo@example.com"), msg
    assert_includes password_errors("Glacier#Mild9Smith!", email_address: "jane.smith@lab.org"), msg
  end

  test "a password can't be the current one or any used before" do
    user = User.create!(valid_user_attrs)
    user.update!(password: OTHER_GOOD_PASSWORD, password_confirmation: OTHER_GOOD_PASSWORD)

    user.password = user.password_confirmation = OTHER_GOOD_PASSWORD # the current one
    assert_not user.valid?
    assert_includes user.errors[:password], "must not be one you've used before"

    user.password = user.password_confirmation = GOOD_PASSWORD # the one before
    assert_not user.valid?
    assert_includes user.errors[:password], "must not be one you've used before"
  end

  # has_secure_password keeps the plain password on the object after saving;
  # the policy used to check it again on the next save and refuse it as used.
  test "saving the same user again after setting a password isn't refused" do
    user = User.create!(valid_user_attrs)
    assert user.update(name: "renamed_user"), user.errors.full_messages.inspect
  end

  test "PASSWORD_HISTORY limits how far back reuse is refused" do
    Rails.application.config.x.password_history = 1
    user = User.create!(valid_user_attrs)
    user.update!(password: OTHER_GOOD_PASSWORD, password_confirmation: OTHER_GOOD_PASSWORD)
    assert_equal 1, user.password_histories.count
    user.password = user.password_confirmation = GOOD_PASSWORD # two back: allowed again
    assert user.valid?, user.errors.full_messages.inspect
  ensure
    Rails.application.config.x.password_history = nil
  end

  test "choosing a password stamps it; a generated one doesn't count as chosen" do
    user = User.create!(valid_user_attrs)
    assert_not user.password_expired?
    assert_equal 1, user.password_histories.count

    generated = User.new(name: "gen", email_address: "gen@example.com")
    generated.assign_generated_password
    generated.save!
    assert generated.password_expired?, "nobody has chosen this account's password yet"
    assert_empty generated.password_histories
  end

  test "a password expires once it's older than PASSWORD_MAX_AGE_DAYS" do
    user = User.create!(valid_user_attrs)
    user.update_columns(password_changed_at: (User.password_max_age + 1.day).ago)
    assert user.password_expired?
    user.update_columns(password_changed_at: (User.password_max_age - 1.day).ago)
    assert_not user.password_expired?
  end

  test "allows nil password on existing user" do
    alice = users(:alice)
    alice.name = "alice_renamed"
    assert alice.save
  end

  test "create_activation_digest is set before create" do
    user = User.create!(valid_user_attrs)
    assert_not_nil user.activation_digest
    assert_not_nil user.activation_token
  end

  test "activate sets flags and timestamps" do
    user = users(:unactivated)
    assert_not user.activated?
    user.activate
    user.reload
    assert user.activated?
    assert_not_nil user.activated_at
    assert_not_nil user.confirmed_at
  end

  test "authenticated? returns false when digest is nil" do
    user = users(:alice)
    user.update_columns(reset_digest: nil)
    assert_not user.authenticated?(:reset, "anything")
  end

  test "authenticated? matches the token" do
    user = users(:alice)
    user.reset_token = User.new_token
    user.update(reset_digest: User.digest(user.reset_token))
    assert user.authenticated?(:reset, user.reset_token)
    assert_not user.authenticated?(:reset, "wrong-token")
  end

  test "create_reset_digest populates reset fields" do
    user = users(:alice)
    user.create_reset_digest
    assert_not_nil user.reset_digest
    assert_not_nil user.reset_sent_at
    assert_not_nil user.reset_token
  end

  test "password_reset_expired? true when sent over 2 hours ago" do
    user = users(:alice)
    user.update_attribute(:reset_sent_at, 3.hours.ago)
    assert user.password_reset_expired?
    user.update_attribute(:reset_sent_at, 30.minutes.ago)
    assert_not user.password_reset_expired?
  end

  test "account_type reflects role" do
    assert_equal "admin", users(:admin).account_type
    assert_equal "basic", users(:alice).account_type
  end

  test "sorted_projects returns user's projects in name order" do
    assert_equal %w[alpha_project beta_project], users(:alice).sorted_projects.pluck(:name)
  end

  test "make_anon builds an anon user with matching email and name" do
    user = User.make_anon
    user.save!
    assert user.anon
    assert user.name.present?
    assert_equal "#{user.name.downcase}@example.org", user.email_address
  end
end
