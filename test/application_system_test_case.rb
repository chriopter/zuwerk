require "test_helper"
require "capybara/rails"
require "selenium/webdriver"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driver_path = ENV["CHROMEDRIVER_PATH"]
  driver_path ||= "/usr/bin/chromedriver" if File.executable?("/usr/bin/chromedriver")
  Selenium::WebDriver::Chrome::Service.driver_path = driver_path if driver_path

  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1000 ] do |options|
    options.add_argument("--no-sandbox")
    options.add_argument("--disable-dev-shm-usage")
  end
end
