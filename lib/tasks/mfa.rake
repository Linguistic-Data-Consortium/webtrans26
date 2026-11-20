# The way back for someone who has lost both their authenticator and their
# recovery codes (User::Mfa). Check who they are first: this lets the next
# person to sign in with their password set up a new authenticator.
namespace :mfa do
  desc "Clear a user's two-step sign-in so they set it up again: EMAIL=address"
  task reset: :environment do
    user = User.find_by(email_address: ENV.fetch("EMAIL") { abort "Usage: bin/rails mfa:reset EMAIL=address" })
    abort "No user with that email address." unless user
    user.reset_mfa!
    user.sessions.destroy_all
    SecurityEvent.record("mfa.reset", user: user, via: "bin/rails mfa:reset")
    puts "Two-step sign-in cleared for #{user.name}; they'll set it up again at their next sign-in."
  end
end
