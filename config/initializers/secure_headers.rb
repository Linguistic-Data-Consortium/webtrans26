SecureHeaders::Configuration.default do |config|
  # Prevent framing to protect against clickjacking attacks
  # DENY = cannot be framed at all
  # SAMEORIGIN = can only be framed by same origin
  config.x_frame_options = "DENY"

  # Prevent MIME type sniffing
  # Stops browsers from guessing content types
  config.x_content_type_options = "nosniff"

  # Enable XSS protection for older browsers
  # Modern browsers use CSP instead, but this provides defense-in-depth
  config.x_xss_protection = "1; mode=block"

  # Prevent downloads from opening automatically in Internet Explorer
  config.x_download_options = "noopen"

  # Restrict Adobe Flash/PDF cross-domain policies
  config.x_permitted_cross_domain_policies = "none"

  # Control referrer information sent with requests
  # origin-when-cross-origin = send full URL for same-origin, only origin for cross-origin
  config.referrer_policy = %w[origin-when-cross-origin strict-origin-when-cross-origin]

  # Content Security Policy (CSP)
  # This is the most important security header - it prevents XSS attacks

  # Build script_src based on environment
  script_sources = %w['self' 'unsafe-inline' 'unsafe-eval' https://cdnjs.cloudflare.com https://cdn.jsdelivr.net]
  script_sources << 'http://localhost:3036' if Rails.env.development?

  # Build style_src based on environment
  style_sources = %w['self' 'unsafe-inline' https://cdn.tailwindcss.com]
  style_sources << 'http://localhost:3036' if Rails.env.development?

  # Build connect_src based on environment
  connect_sources = %w['self' wss: https: *.amazonaws.com]
  connect_sources += %w[ws: http:] if Rails.env.development?

  config.csp = {
    # Default policy for all content types not explicitly listed
    default_src: %w['self'],

    # Scripts: Allow from same origin + inline scripts + eval
    # NOTE: 'unsafe-inline' and 'unsafe-eval' reduce security but are needed for:
    # - Vite dev server hot module replacement
    # - Svelte runtime compilation
    # - Some legacy JS patterns in the app
    # - CDN scripts (jQuery, JSZip, Marked, AWS SDK from cdnjs.cloudflare.com)
    # - jsDelivr CDN (cdn.jsdelivr.net)
    # TODO: Remove 'unsafe-eval' after verifying no eval statements remain in JS
    script_src: script_sources,

    # Styles: Allow from same origin + inline styles + Tailwind CDN
    style_src: style_sources,

    # Images: Allow from same origin, data URIs, and AWS S3
    img_src: %w['self' data: https: *.amazonaws.com],

    # AJAX/WebSocket connections: Allow same origin, wss, https, and AWS
    # In development, also allow ws: and http: for Vite dev server
    connect_src: connect_sources,

    # Fonts: Allow from same origin and data URIs
    font_src: %w['self' data:],

    # Media (audio/video): Allow from same origin and AWS S3
    # Fixed: Use https://*.amazonaws.com instead of *.amazonaws.com for proper CSP syntax
    # Added blob: for Web Audio API and data: for data URIs
    media_src: %w['self' https: https://*.amazonaws.com blob: data:],

    # Frames/iframes: Don't allow any framing
    frame_src: %w['none'],

    # Objects (Flash, Java, etc.): Don't allow any
    object_src: %w['none'],

    # Base URI: Only allow same origin (prevents base tag injection)
    base_uri: %w['self'],

    # Form actions: Only allow forms to submit to same origin
    form_action: %w['self'],

    # Report violations to console in development
    # In production, consider adding report_uri to log violations
    # report_uri: %w[/csp-violation-report]
  }

  # HTTP Strict Transport Security (HSTS)
  # Forces browsers to use HTTPS for all future requests
  # Only enable in production where HTTPS is available
  if Rails.env.production?
    # max-age: 1 year in seconds
    # includeSubDomains: apply to all subdomains
    # preload: eligible for browser HSTS preload list
    config.hsts = "max-age=#{1.year.to_i}; includeSubDomains; preload"
  else
    # Disable HSTS in development (running on HTTP)
    config.hsts = SecureHeaders::OPT_OUT
  end

  # Expect-CT header (Certificate Transparency)
  # Helps detect misissued certificates
  # Optional - only useful if you have CT monitoring set up
  # config.expect_ct = "max-age=86400, enforce"
end

# Test environment overrides (if needed)
if Rails.env.test?
  SecureHeaders::Configuration.override(:test) do |config|
    # Disable CSP in tests to avoid conflicts with test frameworks
    config.csp = SecureHeaders::OPT_OUT
  end
end
