# frozen_string_literal: true

require "json"
require "yaml"
require "date"

module PriceMonitor
  ROOT = File.expand_path("..", __dir__)

  def self.path(*parts) = File.join(ROOT, *parts)

  def self.services_config
    YAML.safe_load_file(path("config", "services.yml"))
  end
end

require_relative "price_monitor/extractor"
require_relative "price_monitor/history"
require_relative "price_monitor/differ"
require_relative "price_monitor/notifier"
require_relative "price_monitor/calculator"
require_relative "price_monitor/site"
require_relative "price_monitor/margherita"
