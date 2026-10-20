class User < ApplicationRecord
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

  validates :password, presence: true, length: { minimum: 8 }, allow_nil: true

  scope :all_activated, -> { where(:activated => true) }
  has_many :project_users, :dependent => :destroy
  has_many :projects, :through => :project_users
  has_many :task_users, :dependent => :destroy
  has_many :tasks, :through => :task_users
  has_many :group_users, :dependent => :destroy
  has_many :groups, :through => :group_users
  belongs_to :current_task_user, :class_name => 'TaskUser', optional: true

  scope :sorted, -> { order('name ASC') }


  def self.make_anon
    name = new_token
    pw = new_token
    new name: name, email_address: "#{name}@example.org", password: pw, password_confirmation: pw, anon: true
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

  def authenticated?(att, token)
    digest = send "#{att}_digest"
    return false if digest.nil?
    BCrypt::Password.new(digest).is_password?(token)
  end

  def forget
    update_attribute(:remember_digest, nil)
  end

  def activate
    now = Time.zone.now
    update_columns( activated: true, activated_at: now, confirmed_at: now)
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
    self.password = User.new_token # avoid db error
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

  def create_activation_digest
    self.activation_token  = User.new_token
    self.activation_digest = User.digest(activation_token)
  end

end
