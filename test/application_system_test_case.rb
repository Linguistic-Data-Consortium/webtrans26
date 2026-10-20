require "test_helper"
require "capybara/rails"
require "selenium-webdriver"

# Selenium Manager and DriverFinder both prefer chromedriver found on PATH, which may be an
# outdated Homebrew install. We invoke selenium-manager with PATH scrubbed of Homebrew/local bin
# dirs so it is forced to use its own cached, version-matched driver.
def resolve_managed_chromedriver
  platform_dir = case RUBY_PLATFORM
                 when /darwin/ then "macos"
                 when /mingw|mswin/ then "windows"
                 else "linux"
                 end
  suffix = platform_dir == "windows" ? ".exe" : ""
  sm_bin = File.join(Gem.loaded_specs["selenium-webdriver"].full_gem_path, "bin", platform_dir, "selenium-manager#{suffix}")

  scrubbed_path = ENV["PATH"].to_s.split(File::PATH_SEPARATOR)
                                   .reject { |d| d =~ %r{/(homebrew|usr/local)/bin\z} }
                                   .join(File::PATH_SEPARATOR)

  output = IO.popen({ "PATH" => scrubbed_path }, [sm_bin, "--browser", "chrome", "--output", "json"], err: File::NULL, &:read)
  path = JSON.parse(output).dig("result", "driver_path")
  path if path && !path.empty?
rescue StandardError
  nil
end

Capybara.register_driver :managed_headless_chrome do |app|
  options = Selenium::WebDriver::Chrome::Options.new
  options.add_argument("--headless=new")
  options.add_argument("--disable-gpu")
  options.add_argument("--no-sandbox")
  options.add_argument("--window-size=1400,1400")
  options.add_option("goog:loggingPrefs", { "browser" => "ALL" })

  driver_path = resolve_managed_chromedriver
  service = driver_path ? Selenium::WebDriver::Service.chrome(path: driver_path) : Selenium::WebDriver::Service.chrome
  Capybara::Selenium::Driver.new(app, browser: :chrome, options: options, service: service)
end

# Capybara's 2-second default is too tight for this suite: it runs 8 headless
# Chromes in parallel on one machine, and the dashboard has to boot a Svelte app
# before most assertions can pass. Under that contention a sign-in redirect or a
# key binding can take longer than 2s, which showed up as tests failing on a page
# they simply hadn't navigated away from yet. Most assertions in these files
# already pass `wait: 5` by hand; this makes that the default.
Capybara.default_max_wait_time = 5

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  include MailToggleHelpers

  driven_by :managed_headless_chrome

  # CSRF is off by default in the test env, but the Svelte dashboard's `getp` helper reads
  # the `<meta name="csrf-token">` tag and crashes if it isn't rendered. Re-enable forgery
  # protection for system tests — Capybara-driven form submissions include the token automatically.
  setup do
    @_allow_forgery_protection_was = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
  end

  teardown do
    ActionController::Base.allow_forgery_protection = @_allow_forgery_protection_was
  end
end
