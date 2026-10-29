# frozen_string_literal: true

require "net/http"
require "uri"

module PriceMonitor
  # Telegram si TELEGRAM_BOT_TOKEN e TELEGRAM_CHAT_ID stanno mise,
  # sinnò stampa ncopp' a stdout (comodo 'n locale e dint' 'e log d' 'a CI).
  class Notifier
    def initialize(token: ENV["TELEGRAM_BOT_TOKEN"], chat_id: ENV["TELEGRAM_CHAT_ID"], io: $stdout)
      @token = token
      @chat_id = chat_id
      @io = io
    end

    def notify(text)
      @io.puts(text)
      return unless @token && @chat_id

      uri = URI("https://api.telegram.org/bot#{@token}/sendMessage")
      res = Net::HTTP.post_form(uri, "chat_id" => @chat_id, "text" => text)
      warn "Telegram: #{res.code} #{res.body}" unless res.is_a?(Net::HTTPSuccess)
    rescue StandardError => e
      warn "Notifica non inviata: #{e.message}"
    end
  end
end
