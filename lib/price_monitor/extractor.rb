# frozen_string_literal: true

module PriceMonitor
  # Caccia 'e prezze d' 'o TESTO 'e na paggena (no d' 'o HTML), accussì si
  # cagnano 'e classe CSS nun se rompe niente: conta sulo chello ca legge 'a gente.
  #
  # Pe' ogni piano cerca 'a primma riga ca piglia `match` (e no `exclude`),
  # po' 'o primmo prezzo in euro ncopp' a chella riga o a chelle 'e sotto.
  class Extractor
    # "6,99 €", "€ 6,99", "6.99€", "EUR 6,99"
    PRICE_RE = /(?:€|EUR)\s*(\d{1,3}[.,]\d{2})|(\d{1,3}[.,]\d{2})\s*(?:€|EUR)/i

    Result = Struct.new(:prices, :errors, keyword_init: true) do
      def ok? = errors.empty?
    end

    def initialize(plans_config)
      @plans = plans_config
    end

    def call(text)
      lines = normalize(text)
      prices = {}
      errors = []

      @plans.each do |plan_id, cfg|
        price = find_price(lines, cfg)
        if price.nil?
          errors << "#{plan_id}: piano o prezzo non trovato"
        elsif !plausible?(price, cfg)
          errors << "#{plan_id}: prezzo #{price} fuori range #{cfg['min']}-#{cfg['max']}"
        else
          prices[plan_id] = price
        end
      end

      Result.new(prices: prices, errors: errors)
    end

    private

    def normalize(text)
      text = text.dup.force_encoding(Encoding::UTF_8)   # file liggiute cu 'o locale ASCII
      text.scrub.gsub(" ", " ")           # spazie ca nun se spartono, se trovano spisso dint' 'e prezze
          .lines.map(&:strip).reject(&:empty?)
    end

    def find_price(lines, cfg)
      match   = Regexp.new(cfg.fetch("match"), Regexp::IGNORECASE)
      exclude = cfg["exclude"] && Regexp.new(cfg["exclude"], Regexp::IGNORECASE)
      ahead   = cfg.fetch("lookahead", 6)

      lines.each_with_index do |line, i|
        next unless line.match?(match)
        next if exclude && line.match?(exclude)

        lines[i..(i + ahead)].each do |candidate|
          m = candidate.match(PRICE_RE)
          return to_f(m[1] || m[2]) if m
        end
      end
      nil
    end

    def plausible?(price, cfg)
      min = cfg.fetch("min", 0.5)
      max = cfg.fetch("max", 100)
      price.between?(min, max)
    end

    def to_f(str) = str.tr(",", ".").to_f.round(2)
  end
end
