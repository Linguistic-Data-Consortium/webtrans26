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
        if user
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

    user.activate unless user.activated?
    user.clear_access_digest # single use
    start_new_session_for user
    redirect_to root_path, notice: "Welcome, #{user.name}."
  end

  private

  def create_and_mint(name, email)
    password = User.new_token
    user = User.new(
      name: name,
      email_address: email,
      password: password,
      password_confirmation: password
    )
    if user.save
      mint user
    else
      { errors: user.errors.full_messages }
    end
  end

  def mint(user)
    token = user.create_access_digest(current_user.id)
    {
      ok: "access link created for #{user.name}",
      name: user.name,
      email: user.email_address,
      activated: user.activated,
      url: access_link_url(user.id, token)
    }
  end
end
