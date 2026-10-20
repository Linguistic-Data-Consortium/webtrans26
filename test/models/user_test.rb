require "test_helper"

class UserTest < ActiveSupport::TestCase
  def valid_user_attrs(overrides = {})
    {
      name: "newuser",
      email_address: "new@example.com",
      password: "password123",
      password_confirmation: "password123"
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

  test "requires password at least 8 chars" do
    user = User.new(valid_user_attrs(password: "short", password_confirmation: "short"))
    assert_not user.valid?
    assert user.errors[:password].any?
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
