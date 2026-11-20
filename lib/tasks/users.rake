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

  # The logged ways to do what used to take the console. Each records who it
  # was done to in the security log (SecurityEvent); there's no signed-in actor
  # from a shell, so via: says where it came from.
  def find_user_or_abort
    email = ENV.fetch("EMAIL") { abort "Usage: bin/rails #{ARGV.first} EMAIL=address" }
    User.find_by(email_address: email.strip.downcase) || abort("No user with that email address.")
  end

  desc "Deactivate an account and sign it out everywhere: EMAIL=address"
  task deactivate: :environment do
    user = find_user_or_abort
    user.deactivate
    puts "#{user.name} deactivated and signed out. Re-activate from the Activations tab."
  end

  desc "Make a user a system admin: EMAIL=address"
  task grant_admin: :environment do
    user = find_user_or_abort
    user.update_attribute(:admin, true) # callbacks (and so the log) without re-validating an old account
    puts "#{user.name} is now a system admin."
  end

  desc "Take system admin away from a user: EMAIL=address"
  task revoke_admin: :environment do
    user = find_user_or_abort
    user.update_attribute(:admin, false)
    puts "#{user.name} is no longer a system admin."
  end
end

