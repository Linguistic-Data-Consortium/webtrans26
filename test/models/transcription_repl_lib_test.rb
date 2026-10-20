require "test_helper"
require "selenium-webdriver"
require Rails.root.join("script/transcription_repl_lib")

# The REPL scripts hand control to a human and wait for them to close the
# browser. How "closed" presents itself depends on the setup, so the wait has to
# recognise both forms — an empty window list and a dead session.
class TranscriptionReplLibTest < ActiveSupport::TestCase
  # Returns each queued value in turn; a value that is an exception is raised.
  class FakeDriver
    def initialize(*responses) = @responses = responses
    def window_handles
      response = @responses.shift
      raise response if response.is_a?(Exception) || (response.is_a?(Class) && response <= Exception)
      response
    end
  end

  def wait(driver)
    TranscriptionReplLib.wait_for_browser_close(driver, interval: 0)
  end

  test "returns once the window list is empty" do
    driver = FakeDriver.new([ "window-1" ], [ "window-1" ], [])
    assert_nothing_raised { wait(driver) }
  end

  # Regression: the loop used to poll window_handles and only break on an
  # exception, so a browser whose process outlives its last window (a real
  # Chrome on macOS) left the script spinning forever.
  test "an empty list ends the wait even though nothing was raised" do
    driver = FakeDriver.new([])
    assert_nothing_raised { wait(driver) }
  end

  test "returns when the session has gone away" do
    [ Selenium::WebDriver::Error::NoSuchWindowError,
      Selenium::WebDriver::Error::InvalidSessionIdError ].each do |error|
      driver = FakeDriver.new([ "window-1" ], error.new("gone"))
      assert_nothing_raised { wait(driver) }
    end
  end

  test "returns on a webdriver error whose message says the browser is gone" do
    driver = FakeDriver.new(Selenium::WebDriver::Error::WebDriverError.new("disconnected: not connected to DevTools"))
    assert_nothing_raised { wait(driver) }
  end

  test "an unrelated webdriver error is not swallowed" do
    driver = FakeDriver.new(Selenium::WebDriver::Error::WebDriverError.new("something else entirely"))
    assert_raises(Selenium::WebDriver::Error::WebDriverError) { wait(driver) }
  end
end
