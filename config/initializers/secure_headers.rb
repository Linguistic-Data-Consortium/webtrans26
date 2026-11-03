SecureHeaders::Configuration.default do |config|
  # Prevent framing to protect against clickjacking attacks
  # DENY = cannot be framed at all
  # SAMEORIGIN = can only be framed by same origin
  config.x_frame_options = "DENY"

  # Prevent MIME type sniffing
  # Stops browsers from guessing content types
  config.x_content_type_options = "nosniff"

  # The legacy XSS auditor is off: modern browsers have dropped it, and where it
  # survives its blocking mode could be abused to disable scripts selectively.
  # The CSP is the protection.
  config.x_xss_protection = "0"

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
  # blob: is for in-browser speech recognition. worker_src below lets the
  # Worker be created; this is the step after that — onnxruntime-web loads its
  # own glue script from a blob: URL inside the Worker, and a script load is
  # governed by script_src (script-src-elem is unset, so it falls back here).
  # Without it the console says
  #     Loading the script 'blob:https://…' violates … "script-src 'self' …"
  # and the engine never starts.
  #
  #
  # No 'unsafe-inline': the layout's one inline script carries a per-request nonce
  # (nonced_javascript_tag), which secure_headers adds here, so an injected
  # <script> or onerror= handler doesn't run.
  #
  # 'unsafe-eval' stays for now. The onnxruntime build that local ASR loads
  # (ort-wasm-simd-threaded.asyncify) compiles embind method callers with
  # `new Function`, and its Worker, made from a blob:, inherits this policy.
  # Nothing in app/javascript itself evaluates strings.
  #
  # The CDN scripts are named by exact path, not by host, so the rest of cdnjs
  # (which includes libraries known to defeat a CSP) isn't admitted. The layout
  # pins the same files by SRI hash.
  CDN_SCRIPTS = %w[
    https://cdnjs.cloudflare.com/ajax/libs/jquery/3.6.0/jquery.js
    https://cdnjs.cloudflare.com/ajax/libs/jszip/3.7.1/jszip.min.js
  ]
  script_sources = %w['self' 'unsafe-eval' blob:] + CDN_SCRIPTS
  script_sources << 'http://localhost:3036' if Rails.env.development?

  # Build style_src based on environment
  style_sources = %w['self' 'unsafe-inline' https://cdn.tailwindcss.com]
  style_sources << 'http://localhost:3036' if Rails.env.development?

  # Build connect_src based on environment
  #
  # Deliberately broad for now, as is media_src below: kit audio can be a
  # plain https URL on any host, fetched both as <audio> and for waveform
  # ranges, and which hosts to allow hasn't been decided.
  #
  # The decision is open and it is not this app's alone -- the same policy is in
  # the sibling apps. It is written up in claudeq/app_comparison, as
  # surveys/open-security-questions.md (item 1). Read it before narrowing
  # either list.
  connect_sources = %w['self' wss: https: *.amazonaws.com]
  connect_sources += %w[ws: http:] if Rails.env.development?

  config.csp = {
    # Default policy for all content types not explicitly listed
    default_src: %w['self'],

    # Scripts: see script_sources above.
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

    # Workers: same origin, plus blob: URLs.
    #
    # There is no default for this. Without worker_src a Worker falls back to
    # default_src, which is 'self' alone — so a bundled worker loads but the
    # blob: workers that onnxruntime-web and some bundlers create do not, and
    # the failure arrives as a CSP violation in the console rather than as an
    # error the calling code can report. In-browser speech recognition
    # (ports/local-stt.md) runs in a Worker, which is why this is here.
    worker_src: %w['self' blob:],

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
