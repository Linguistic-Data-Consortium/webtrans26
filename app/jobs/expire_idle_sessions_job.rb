# Every 10 minutes (config/recurring.yml): end sessions unused past the idle
# limit and log each one (Session.expire!). A session is also ended when its
# cookie next turns up; this catches the ones that never do, so the security
# log has every timeout and the table doesn't keep dead rows.
class ExpireIdleSessionsJob < ApplicationJob
  queue_as :default

  def perform
    Session.idle.includes(:user).find_each.count { |s| Session.expire!(s, via: "sweep") }
  end
end
