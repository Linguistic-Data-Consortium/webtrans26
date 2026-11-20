# Daily (config/recurring.yml): disable every account unused for
# INACTIVE_ACCOUNT_DAYS (User#inactive_too_long?). Sign-in checks too, so an
# instance without a job runner still enforces the limit; this keeps the
# admin's list of inactive accounts true in the meantime.
class DisableInactiveAccountsJob < ApplicationJob
  queue_as :default

  def perform
    count = User.disable_inactive!
    Rails.logger.info "[DisableInactiveAccountsJob] disabled #{count} account#{'s' unless count == 1} unused for #{User.inactive_after.in_days.to_i} days"
    count
  end
end
