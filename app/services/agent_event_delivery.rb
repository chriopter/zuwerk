require "json"
require "net/http"
require "openssl"
require "uri"

class AgentEventDelivery
  class DeliveryError < StandardError; end
  class ConfigurationError < DeliveryError; end

  ERROR_LIMIT = 255

  def initialize(event, url:, secret:, clock: -> { Time.current })
    @event = event
    @url = url
    @secret = secret
    @clock = clock
  end

  def deliver
    @event.with_lock do
      return if @event.delivered_at?

      validate_configuration!
      body = JSON.generate(@event.payload)
      timestamp = @clock.call.to_i.to_s
      response = post(body, timestamp)
      raise DeliveryError, "Webhook returned HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      @event.update!(delivered_at: Time.current, last_error: nil)
    end
  rescue => error
    record_failure(error)
    raise if error.is_a?(DeliveryError)

    raise DeliveryError, "Webhook delivery failed: #{error.class}"
  end

  private
    def validate_configuration!
      if @url.blank? || @secret.blank?
        raise ConfigurationError, "Webhook URL and secret must be configured"
      end
    end

    def post(body, timestamp)
      uri = URI.parse(@url)
      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      request["X-Webhook-Timestamp"] = timestamp
      request["X-Webhook-Signature-V2"] = OpenSSL::HMAC.hexdigest("SHA256", @secret, "#{timestamp}.#{body}")
      request["X-Webhook-Delivery"] = @event.public_id
      request.body = body

      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 5, read_timeout: 10) do |http|
        http.request(request)
      end
    end

    def record_failure(error)
      message = error.is_a?(DeliveryError) ? error.message : "Webhook delivery failed: #{error.class}"
      @event.update_columns(attempts: @event.attempts + 1, last_error: message.truncate(ERROR_LIMIT), updated_at: Time.current)
    end
end
