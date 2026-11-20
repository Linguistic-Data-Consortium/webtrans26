class Current < ActiveSupport::CurrentAttributes
  attribute :session
  # The request's address and browser, so the security log can say where an
  # event came from even when a model records it (SecurityEvent.record).
  attribute :ip, :user_agent
  delegate :user, to: :session, allow_nil: true
end
