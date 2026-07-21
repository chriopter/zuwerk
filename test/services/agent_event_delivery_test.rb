require "test_helper"
require "socket"

class AgentEventDeliveryTest < ActiveSupport::TestCase
  setup do
    human = User.create!(name: "Human", email: "delivery-human@example.com", password: "password1")
    agent = User.create!(name: "Hermes", kind: :agent)
    @event = Message.create!(author: human, body: "secret body @hermes").agent_events.sole
  end

  test "sends signed trigger-only JSON and marks the event delivered" do
    response = capture_request(response_status: "204 No Content") do |url, request_queue|
      AgentEventDelivery.new(@event, url: url, secret: "test-secret", clock: -> { Time.at(1_700_000_000) }).deliver
      request_queue.pop
    end

    headers, body = response
    expected_signature = OpenSSL::HMAC.hexdigest("SHA256", "test-secret", "1700000000.#{body}")
    assert_equal "1700000000", headers["x-webhook-timestamp"]
    assert_equal expected_signature, headers["x-webhook-signature-v2"]
    assert_equal @event.public_id, headers["x-webhook-delivery"]
    assert_equal "application/json", headers["content-type"]
    assert_equal @event.public_id, JSON.parse(body).fetch("id")
    assert_not_includes body, "secret body"
    assert @event.reload.delivered_at?
    assert_equal 0, @event.attempts
  end

  test "records a safe bounded error and raises when HTTP delivery fails" do
    assert_raises(AgentEventDelivery::DeliveryError) do
      capture_request(response_status: "503 Service Unavailable", response_body: "sensitive response") do |url, _request_queue|
        AgentEventDelivery.new(@event, url: url, secret: "test-secret").deliver
      end
    end

    @event.reload
    assert_equal 1, @event.attempts
    assert_equal "Webhook returned HTTP 503", @event.last_error
    assert_not_includes @event.last_error, "sensitive"
  end

  test "missing configuration records an error and raises without delivery" do
    error = assert_raises(AgentEventDelivery::ConfigurationError) do
      AgentEventDelivery.new(@event, url: "", secret: "").deliver
    end

    assert_equal "Webhook URL and secret must be configured", error.message
    assert_equal 1, @event.reload.attempts
    assert_equal error.message, @event.last_error
  end

  test "wraps network failures so the job retry policy handles them" do
    error = assert_raises(AgentEventDelivery::DeliveryError) do
      AgentEventDelivery.new(@event, url: "http://127.0.0.1:1/hook", secret: "test-secret").deliver
    end

    assert_match(/Webhook delivery failed:/, error.message)
    assert_equal 1, @event.reload.attempts
    assert_match(/Webhook delivery failed:/, @event.last_error)
  end

  test "already delivered event returns without another request" do
    @event.update!(delivered_at: Time.current)

    assert_nil AgentEventDelivery.new(@event, url: "http://127.0.0.1:1", secret: "secret").deliver
  end

  private
    def capture_request(response_status:, response_body: "")
      server = TCPServer.new("127.0.0.1", 0)
      requests = Queue.new
      thread = Thread.new do
        socket = server.accept
        head = socket.readpartial(16_384)
        headers_text, body = head.split("\r\n\r\n", 2)
        lines = headers_text.lines.map(&:strip)
        headers = lines.drop(1).to_h { |line| line.split(": ", 2).map(&:downcase) }
        content_length = headers.fetch("content-length").to_i
        body = body.to_s + socket.read(content_length - body.to_s.bytesize).to_s
        requests << [ headers, body ]
        socket.write "HTTP/1.1 #{response_status}\r\nContent-Length: #{response_body.bytesize}\r\nConnection: close\r\n\r\n#{response_body}"
        socket.close
      ensure
        server.close
      end

      yield "http://127.0.0.1:#{server.local_address.ip_port}/hook", requests
    ensure
      thread&.join
      server&.close unless server&.closed?
    end
end
