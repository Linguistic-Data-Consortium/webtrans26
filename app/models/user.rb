class User < ApplicationRecord
  include User::Mfa
  has_secure_password
  has_many :sessions, dependent: :destroy

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  attr_accessor :remember_token, :activation_token, :reset_token, :invite_token, :access_token
  # before_save :downcase_email
  before_create :create_activation_digest
  VALID_USERNAME_REGEX  = /\A[-a-zA-Z0-9_.]+\Z/
  validates :name, presence: true, length: { maximum: 30 }, format: { with: VALID_USERNAME_REGEX }, uniqueness: { case_sensitive: false }
  VALID_EMAIL_REGEX = /\A[-\w+.]+@([-a-z\d]+\.)+[a-z]+\z/i
  validates :email_address, presence: true, length: { maximum: 255 }, format: { with: VALID_EMAIL_REGEX }, uniqueness: { case_sensitive: false }

  validates :password, presence: true, allow_nil: true
  # The rules for a chosen password (PasswordPolicy). A password the app makes
  # up itself, for an account nobody has chosen one for yet, is exempt.
  # Only when it's being changed: has_secure_password keeps the plain password
  # on the object after it's saved, and checking it again on a later save would
  # refuse it as one used before.
  validate :password_meets_policy,
           if: -> { password.present? && will_save_change_to_password_digest? && !@password_generated }

  has_many :password_histories, -> { order(created_at: :desc) }, dependent: :delete_all
  before_save :stamp_password_change, if: :will_save_change_to_password_digest?
  after_save :remember_password, if: :saved_change_to_password_digest?

  # How long a chosen password lasts before it must be changed, and how many
  # earlier ones may not be chosen again (nil: all of them). Set by
  # PASSWORD_MAX_AGE_DAYS and PASSWORD_HISTORY (config/application.rb).
  def self.password_max_age = Rails.application.config.x.password_max_age_days.days
  def self.password_history_count = Rails.application.config.x.password_history

  # Give the account a long random password nobody knows, as access links,
  # invites and anonymous accounts need. It isn't the user's choice, so it
  # doesn't count as one: the account is left needing a password chosen.
  def assign_generated_password
    @password_generated = true
    self.password = self.password_confirmation = SecureRandom.base64(48)
  end

  # Sign-in lockout: this many wrong passwords in a row lock the account for
  # LOCKOUT_PERIOD, during which even the right one is refused.
  LOCKOUT_ATTEMPTS = 3
  LOCKOUT_PERIOD = 30.minutes

  def locked?
    locked_until.present? && locked_until > Time.current
  end

  # Count a wrong password, locking the account on the LOCKOUT_ATTEMPTS-th. One
  # UPDATE, so attempts arriving together can't each read the old count. The
  # count starts again from zero once a lock is set, so an account whose lock
  # has run out gets the full number of tries.
  def register_failed_sign_in
    User.where(id: id).update_all([
      "failed_sign_in_count = CASE WHEN failed_sign_in_count + 1 >= ? THEN 0 ELSE failed_sign_in_count + 1 END, " \
      "locked_until = CASE WHEN failed_sign_in_count + 1 >= ? THEN ? ELSE locked_until END",
      LOCKOUT_ATTEMPTS, LOCKOUT_ATTEMPTS, LOCKOUT_PERIOD.from_now
    ])
  end

  # A right password, a completed reset, or an access link: start counting again.
  def clear_sign_in_failures
    return if failed_sign_in_count.zero? && locked_until.nil?
    update_columns(failed_sign_in_count: 0, locked_until: nil)
  end

  # Chosen too long ago, or never chosen at all (a generated password, or one
  # from before this policy, which nothing can check against it).
  def password_expired?
    password_changed_at.nil? || password_changed_at < User.password_max_age.ago
  end

  scope :all_activated, -> { where(:activated => true) }
  has_many :project_users, :dependent => :destroy
  has_many :projects, :through => :project_users
  has_many :task_users, :dependent => :destroy
  has_many :tasks, :through => :task_users
  has_many :group_users, :dependent => :destroy
  has_many :groups, :through => :group_users
  belongs_to :current_task_user, :class_name => 'TaskUser', optional: true

  scope :sorted, -> { order('name ASC') }

  # The projects whose S3 prefix this user may read and write, as integer ids —
  # see S3SessionPolicy. Reading is project membership. Writing is computed
  # from the read set, never independently, so a project you may write is
  # always one you may read.
  def s3_read_project_ids
    project_users.pluck(:project_id).compact.uniq.sort
  end

  def s3_write_project_ids
    readable = s3_read_project_ids
    project_users.includes(project: :s3_upload_task)
                 .select(&:may_write_s3?)
                 .map(&:project_id)
                 .select { |id| readable.include?(id) }
                 .uniq.sort
  end


  def self.make_anon
    name = new_token
    new(name: name, email_address: "#{name}@example.org", anon: true).tap(&:assign_generated_password)
  end

  def self.digest(string)
    cost = ActiveModel::SecurePassword.min_cost ? BCrypt::Engine::MIN_COST :
                                                  BCrypt::Engine.cost
    BCrypt::Password.create(string, cost: cost)
  end

  def self.new_token
    SecureRandom.urlsafe_base64
  end

  def remember
    self.remember_token = User.new_token
    update_attribute(:remember_digest, User.digest(remember_token))
  end

  # Links that act on the account without its password stop working after a
  # week: an access link signs its holder in, and an invite lets them set the
  # account up. Each is keyed to the column recording when it was issued.
  TOKEN_LIFETIMES = {
    access: [ :access_created_at, 7.days ],
    invite: [ :invite_sent_at, 7.days ]
  }

  def authenticated?(att, token)
    digest = send "#{att}_digest"
    return false if digest.nil?
    if (issued_column, lifetime = TOKEN_LIFETIMES[att.to_sym])
      issued = send(issued_column)
      return false if issued.nil? || issued < lifetime.ago
    end
    BCrypt::Password.new(digest).is_password?(token)
  end

  def forget
    update_attribute(:remember_digest, nil)
  end

  # Also how an administrator re-enables an account disabled for inactivity,
  # so the clock starts again from now.
  def activate
    now = Time.zone.now
    update_columns( activated: true, activated_at: now, confirmed_at: now, last_active_at: now, disabled_at: nil)
  end

  # ── inactivity ──────────────────────────────────────────────────────────
  #
  # An account nobody has signed in to or used for INACTIVE_ACCOUNT_DAYS is
  # disabled: deactivated, signed out everywhere, and marked disabled_at so the
  # sign-in page and the admin's list can say why. An administrator re-enables
  # it (#activate, from the dashboard's list or an access link).
  # DisableInactiveAccountsJob does this daily; sign-in also checks, so it holds
  # where no job runs.

  def self.inactive_after = Rails.application.config.x.inactive_account_days.days

  scope :inactive_too_long, -> {
    where(activated: true).where("COALESCE(last_active_at, created_at) < ?", inactive_after.ago)
  }

  def self.disable_inactive!
    inactive_too_long.find_each.count(&:disable_for_inactivity!)
  end

  def inactive_too_long?
    activated? && (last_active_at || created_at) < User.inactive_after.ago
  end

  def disabled_for_inactivity?
    !activated? && disabled_at.present?
  end

  def disable_for_inactivity!
    update_columns(activated: false, disabled_at: Time.current)
    sessions.destroy_all
    true
  end

  # Use, as far as inactivity is concerned. Written at most daily: the limit is
  # in days, and this runs on requests.
  def record_activity
    return if last_active_at && last_active_at > 1.day.ago
    update_column(:last_active_at, Time.current)
  end

  # Flips the user back to "not activated" and tears down all live sessions.
  # Used when a password reset is requested on an instance without outbound
  # mail — the user is parked until an administrator verifies them.
  def deactivate
    update_columns(activated: false, activated_at: nil, confirmed_at: nil)
    sessions.destroy_all
  end

  def send_activation_email
    UserMailer.account_activation(self).deliver_now
  end

  def create_reset_digest
    self.reset_token = User.new_token
    update_attribute(:reset_digest,  User.digest(reset_token))
    update_attribute(:reset_sent_at, Time.zone.now)
  end

  # Sends password reset email.
  def send_password_reset_email
    UserMailer.password_reset(self).deliver_now
  end

  def password_reset_expired?
    reset_sent_at < 2.hours.ago
  end

  #returns a sorted list of the user's projects
  def sorted_projects
    projects.order 'name ASC'
  end

   #returns whether a user is at least in the lead annotator group (also returns true for system admins)
  def portal_manager?
    groups.include?(Group.find_by_name 'Portal Managers')
  end

  def project_manager?
    groups.include?(Group.find_by_name 'Project Managers')
  end

  def confirmation_expired?
    confirmed_at.nil? or confirmed_at < 24.hours.ago
  end

  #returns whether a user is at least in the lead annotator group (also returns true for system admins)
  def lead_annotator?
    project_manager?
  end

  def account_type
    if admin?
      "admin"
    elsif lead_annotator?
      "project manager"
    else
      "basic"
    end
  end

  #set the current_task_user_id if its different than the one being annotated on, set the state to paused for the previous taskuser
  def update_current_task_user(task_user)
    #repair the task user if it is in a has_kit state but without a kit_oid assigned
    if task_user.state == 'has_kit' && !task_user.has_kit_oid?
      task_user.goto_state 'needs_kit'
    end

    #repair the current task user if the state is has_kit, but the kit_oid is empty or nil
    if current_task_user && current_task_user.state == 'has_kit' && !current_task_user.has_kit_oid?
      current_task_user.goto_state 'needs_kit'
    end

    #if the current task user and task_user differ, switch the current_task_user
    if current_task_user_id != task_user.id
      #pause the current task user if it exists
      if current_task_user && current_task_user.has_kit_oid?
        current_task_user.goto_state 'paused'
      end

      #unpause the new task_user if it has a kit
      task_user.goto_state 'has_kit' if task_user.state == 'paused' && task_user.has_kit_oid?

      #update the current task_user
      update( :current_task_user_id => task_user.id )
    end
  end

  # One-time sign-in link (AccessLinksController). Mints a token, stores only
  # its digest, and returns the token so the caller can build the URL — it's
  # never recoverable afterwards. Minting again replaces any outstanding link.
  # update_columns skips validations on purpose: legacy rows can be invalid
  # (e.g. no name), and that shouldn't block an administrator issuing a link.
  def create_access_digest(created_by)
    self.access_token = User.new_token
    update_columns(
      access_digest: User.digest(access_token),
      access_created_at: Time.zone.now,
      access_created_by: created_by
    )
    access_token
  end

  # Consuming a link clears the digest — that's what makes it single-use.
  def clear_access_digest
    update_columns(access_digest: nil)
  end

  def access_link_pending?
    access_digest.present?
  end

  def create_invite_digest(sent_by)
    self.invite_token  = User.new_token
    assign_generated_password # avoid db error
    update_attribute(:invite_digest, User.digest(invite_token))
    update_attribute(:invite_sent_at, Time.zone.now)
    update_attribute(:invite_sent_by, sent_by)
  end

  def send_invitation_email
    UserMailer.invite(self).deliver_now
  end

  def send_activation_email_after_updating_digest
    create_activation_digest
    save
    send_activation_email
  end

  private

  def password_meets_policy
    PasswordPolicy.errors_for(password, self).each { |message| errors.add(:password, message) }
  end

  def stamp_password_change
    self.password_changed_at = @password_generated ? nil : Time.current
  end

  # Keep the chosen password's digest, and only as many as the policy looks at.
  def remember_password
    if @password_generated
      @password_generated = false
      return
    end
    password_histories.create!(password_digest: password_digest)
    return unless (keep = User.password_history_count)
    stale = password_histories.offset(keep).pluck(:id)
    PasswordHistory.where(id: stale).delete_all if stale.any?
  end

  def create_activation_digest
    self.activation_token  = User.new_token
    self.activation_digest = User.digest(activation_token)
  end

end
