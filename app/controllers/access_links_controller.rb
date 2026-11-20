# One-time sign-in links, for instances where outbound mail doesn't work and
# the email invite flow (InvitesController) is therefore unusable.
#
# An administrator or portal manager creates the account by name + email and
# gets back a URL. Whoever opens that URL is activated and signed in as that
# user, and the link dies on use — the account's password is random and nobody
# ever needs to know it. To get back in after signing out, the user asks for a
# fresh link or goes through password recovery.
class AccessLinksController < ApplicationController
  allow_unauthenticated_access only: %i[ show ]
  skip_before_action :require_unexpired_password, only: %i[ show ]
  skip_before_action :require_mfa_enrollment, only: %i[ show ]

  # Outstanding (unused) links, so an administrator can see who is still
  # waiting to click one.
  def index
    respondj do
      allow(:portal_manager) do
        {
          users: User.where.not(access_digest: nil).sorted.map do |user|
            {
              id: user.id,
              name: user.name,
              email: user.email_address,
              created_at: user.access_created_at,
              created_by: User.find_by(id: user.access_created_by)&.name,
              activated: user.activated
            }
          end
        }
      end
    end
  end

  # Mint a link. Creates the account when the address is new; for an address
  # that already exists this just issues a fresh link, which is the recovery
  # path for someone who signed out.
  def create
    respondj do
      allow(:portal_manager) do
        email = params[:email_address].to_s.strip
        name = params[:name].to_s.strip
        user = User.find_by(email_address: email.downcase)
        if user && outranks_caller?(user)
          { error: "Only an administrator can create a link for #{user.name}.", status: 403 }
        elsif user
          mint user
        else
          create_and_mint name, email
        end
      end
    end
  end

  # The link itself. Unauthenticated by definition.
  def show
    user = User.find_by(id: params[:id])
    if user.nil? || !user.authenticated?(:access, params[:token].to_s)
      redirect_to new_session_path,
        alert: "That access link is no longer valid. Please ask an administrator for a new one."
      return
    end

    unless user.activated?
      user.activate
      audit("account.activated", user: user, via: "access_link")
    end
    user.clear_access_digest # single use
    audit("access_link.used", user: user)
    user.clear_sign_in_failures # an administrator's link is a way past a lock, too
    # A link stands in for the password, not for the authenticator: with MFA
    # set up, the code is still asked for, and the password page follows.
    if user.mfa_challenge?
      begin_mfa_challenge(user, password_set_without_current: true)
      return redirect_to new_session_mfa_path
    end
    start_new_session_for user
    # The link is how someone gets in without knowing the password, a new
    # account's or a forgotten one, so they choose one now, without being asked
    # for the old one. The flag lives in this session only.
    session[:password_set_without_current] = true
    redirect_to edit_account_password_path, notice: "Welcome, #{user.name}. Choose a password to finish signing in."
  end

  private

  # A link signs its holder in as that user, so minting one is acting as them.
  # A portal manager may do that for anyone below them, not for a peer or an
  # admin: that would turn the portal manager role into admin.
  def outranks_caller?(user)
    return false if admin?
    user.admin? || user.portal_manager?
  end

  def create_and_mint(name, email)
    user = User.new(name: name, email_address: email)
    user.assign_generated_password
    if user.save
      mint user
    else
      { errors: user.errors.full_messages }
    end
  end

  def mint(user)
    token = user.create_access_digest(current_user.id)
    audit("access_link.created", user: user, actor: current_user)
    {
      ok: "access link created for #{user.name}",
      name: user.name,
      email: user.email_address,
      activated: user.activated,
      url: access_link_url(user.id, token)
    }
  end
end
