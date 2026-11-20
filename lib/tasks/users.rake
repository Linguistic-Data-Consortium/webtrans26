namespace :users do
  desc "List accounts past the inactivity limit (INACTIVE_ACCOUNT_DAYS); DISABLE=1 disables them now"
  task inactive: :environment do
    users = User.inactive_too_long.order(:last_active_at).to_a
    users.each { |u| puts "#{u.email_address}\tlast active #{(u.last_active_at || u.created_at).to_date}" }
    if ENV["DISABLE"] == "1"
      users.each(&:disable_for_inactivity!)
      puts "Disabled #{users.size}."
    else
      puts "#{users.size} past #{User.inactive_after.in_days.to_i} days. Run with DISABLE=1 to disable them now."
    end
  end
end
