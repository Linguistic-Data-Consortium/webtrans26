class Session < ApplicationRecord
  belongs_to :user

  # End a session that went unused past the idle limit, and log it: when its
  # cookie next turns up (Authentication#find_session_by_cookie), or from the
  # sweep (ExpireIdleSessionsJob), which catches those never presented again.
  def self.expire!(session, via:)
    session.destroy
    SecurityEvent.record("session.expired", user: session.user, actor: nil, via: via,
                         last_used_at: session.updated_at.utc.iso8601)
  end

  def self.idle
    where(updated_at: ...Authentication.session_idle_timeout.ago)
  end
end
