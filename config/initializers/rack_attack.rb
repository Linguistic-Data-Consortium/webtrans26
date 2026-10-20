class Rack::Attack
  ### Configure Cache ###

  # Use Rails cache for Rack::Attack
  # In production, consider using Redis for distributed rate limiting
  Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new

  ### Throttle Spammy Clients ###

  # Throttle all requests by IP (60 requests per minute)
  # Excludes static assets
  throttle('req/ip', limit: 60, period: 1.minute) do |req|
    req.ip unless req.path.start_with?('/assets', '/vite', '/favicon')
  end

  ### Prevent Brute-Force Login Attacks ###

  # Throttle POST requests to /session by IP address
  # Limit: 5 attempts per 20 seconds
  throttle('logins/ip', limit: 5, period: 20.seconds) do |req|
    if req.path == '/session' && req.post?
      req.ip
    end
  end

  # Throttle POST requests to /session by email param
  # Limit: 5 attempts per 20 seconds per email
  throttle('logins/email', limit: 5, period: 20.seconds) do |req|
    if req.path == '/session' && req.post?
      # Normalize email to prevent case bypasses
      req.params.dig('email_address').to_s.downcase.presence
    end
  end

  ### Prevent Password Reset Spam ###

  # Throttle password reset requests by IP
  # Limit: 3 attempts per 5 minutes
  throttle('password_resets/ip', limit: 3, period: 5.minutes) do |req|
    if req.path == '/passwords' && req.post?
      req.ip
    end
  end

  # Throttle password reset requests by email
  # Limit: 3 attempts per 5 minutes per email
  throttle('password_resets/email', limit: 3, period: 5.minutes) do |req|
    if req.path == '/passwords' && req.post?
      req.params.dig('email_address').to_s.downcase.presence
    end
  end

  ### Prevent Account Activation Spam ###

  # Throttle account activation requests by IP
  # Limit: 10 attempts per 5 minutes
  throttle('account_activations/ip', limit: 10, period: 5.minutes) do |req|
    if req.path.start_with?('/account_activations') && req.get?
      req.ip
    end
  end

  ### Prevent Signup Spam ###

  # Throttle signup requests by IP
  # Limit: 5 signups per hour
  throttle('signups/ip', limit: 5, period: 1.hour) do |req|
    if req.path == '/signup' && req.post?
      req.ip
    end
  end

  ### API Rate Limiting ###

  # General API throttling (if you have API endpoints)
  # Limit: 300 requests per 5 minutes
  throttle('api/ip', limit: 300, period: 5.minutes) do |req|
    if req.path.start_with?('/api')
      req.ip
    end
  end

  ### Custom Throttle Response ###

  # Return 429 status code on throttle with helpful headers
  self.throttled_responder = lambda do |env|
    match_data = env['rack.attack.match_data']
    now = Time.now.to_i
    retry_after = match_data[:period] - (now % match_data[:period])

    headers = {
      'Content-Type' => 'application/json',
      'Retry-After' => retry_after.to_s,
      'X-RateLimit-Limit' => match_data[:limit].to_s,
      'X-RateLimit-Remaining' => '0',
      'X-RateLimit-Reset' => (now + retry_after).to_s
    }

    body = {
      error: 'Rate limit exceeded. Please try again later.',
      retry_after: retry_after
    }.to_json

    [429, headers, [body]]
  end

  ### Logging ###

  # Log blocked requests
  ActiveSupport::Notifications.subscribe('rack.attack') do |name, start, finish, request_id, payload|
    req = payload[:request]

    if [:throttle, :blocklist].include?(req.env['rack.attack.match_type'])
      Rails.logger.warn(
        "[Rack::Attack][#{req.env['rack.attack.match_type']}] " \
        "IP: #{req.ip} | " \
        "Path: #{req.path} | " \
        "Throttle: #{req.env['rack.attack.matched']}"
      )
    end
  end

  ### Blocklist ###

  # Block requests from known bad actors
  # Example: blocklist('block bad IPs') do |req|
  #   ['1.2.3.4', '5.6.7.8'].include?(req.ip)
  # end

  ### Safelist ###

  # Always allow requests from localhost in development
  safelist('allow localhost') do |req|
    req.ip == '127.0.0.1' || req.ip == '::1' if Rails.env.development?
  end
end
