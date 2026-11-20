# The security audit log: one row per event that matters to an account's
# security. Who signed in or failed to, changed a password, set up two-step
# sign-in, was given or lost a role, was disabled.
#
# Append-only: a row can't be changed or deleted through the app. Each event is
# also written to the Rails log as one `[security]` line, for shipping
# elsewhere. Never put a password, code or token in +details+.
#
# Recorded from controllers with Authentication#audit (which adds the request's
# IP, browser and actor), and from jobs, models and tasks with
# SecurityEvent.record. Admins read it at /security_events.
class SecurityEvent < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :actor, class_name: "User", optional: true

  # Every event this records, with what it means. The viewer and the user
  # guide list them from here.
  EVENTS = {
    "sign_in.success"            => "Signed in",
    "sign_in.failure"            => "Wrong password, or an unknown address",
    "sign_in.locked_out"         => "Sign-in refused: the account is locked",
    "sign_in.not_activated"      => "Right password on an account not yet activated",
    "sign_in.disabled"           => "Right password on an account disabled for inactivity",
    "sign_out"                   => "Signed out",
    "account.locked"             => "Locked after too many failed sign-ins",
    "account.created"            => "Signed up",
    "account.activated"          => "Activated (by an administrator, an activation link or an access link)",
    "account.disabled_inactive"  => "Disabled after the inactivity limit",
    "account.deactivated"        => "Deactivated by hand (dashboard, users:deactivate, or the console)",
    "admin.granted"              => "Made a system admin",
    "admin.revoked"              => "No longer a system admin",
    "session.expired"            => "A session ended after the idle limit (found on its next use, or by the sweep every 10 minutes)",
    "project_member.added"       => "Added to a project",
    "project_member.removed"     => "Removed from a project",
    "task_member.added"          => "Added to a task",
    "task_member.removed"        => "Removed from a task",
    "kit_type.changed"           => "A kit type was created, changed or deleted",
    "feature.changed"            => "A feature was created, changed or deleted",
    "workflow.changed"           => "A workflow was created, changed or deleted",
    "password.changed"           => "Changed their password",
    "password.change_failed"     => "Password change refused: wrong current password",
    "password.reset_requested"   => "Asked for a password reset email",
    "password.reset"             => "Set a new password through a reset link",
    "mfa.success"                => "Passed two-step sign-in",
    "mfa.failure"                => "Wrong two-step code",
    "mfa.recovery_code_used"     => "Signed in with a recovery code",
    "mfa.enrolled"               => "Set up two-step sign-in",
    "mfa.recovery_codes_renewed" => "Made new recovery codes",
    "mfa.reset"                  => "Two-step sign-in cleared by an administrator",
    "access_link.created"        => "An access link was made for the account",
    "access_link.used"           => "Signed in with an access link",
    "invite.sent"                => "Invited",
    "group.added"                => "Added to a group (Portal Managers and Project Managers grant roles)",
    "group.removed"              => "Removed from a group",
    "project_role.changed"       => "Project owner or admin flag changed",
    "task_role.changed"          => "Task admin flag changed",
    "download_task.changed"      => "A project's download task was set or cleared (its members may download)",
    "api_token.issued"           => "Issued an API token (/jwts)"
  }.freeze

  validates :event, inclusion: { in: EVENTS.keys }

  scope :newest_first, -> { order(created_at: :desc, id: :desc) }

  def readonly?
    persisted?
  end

  before_destroy { raise ActiveRecord::ReadOnlyRecord, "security events are not deleted" }

  # Record +event+. Never raises: losing an audit row is bad, but failing the
  # sign-in or password change it describes would be worse. A failure is
  # logged instead.
  #
  # From a request, where the request came from and who was signed in fill
  # themselves in (Current); outside one (a job, a task, the console) they're
  # empty. The actor is left out when it's the account itself.
  def self.record(event, user: nil, actor: Current.user, ip: Current.ip, user_agent: Current.user_agent, **details)
    actor = nil if actor && user && actor.id == user.id
    row = create!(event: event, user_id: user&.id, actor_id: actor&.id, ip: ip,
                  user_agent: user_agent&.truncate(255), details: details.compact.presence)
    Rails.logger.info(
      "[security] event=#{event} user=#{user&.id.inspect} actor=#{actor&.id.inspect} ip=#{ip.inspect} " \
      "details=#{details.compact.to_json}"
    )
    row
  rescue => e
    Rails.logger.error("[security] could not record #{event} for user #{user&.id.inspect}: #{e.class}: #{e.message}")
    nil
  end

  def description
    EVENTS[event]
  end
end
