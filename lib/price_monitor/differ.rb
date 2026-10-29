# frozen_string_literal: true

module PriceMonitor
  # Mette a cunfronto 'e prezze appena liggiute cu 'o listino 'e mo' dint' 'o storico.
  # Appunì: cunta sulo 'e piane ca 'o monitor sape leggere (chille d' 'a config),
  # 'e piane annuale o viecchie ca stanno sulo dint' 'o storico nun se cuntano.
  class Differ
    Change = Struct.new(:plan, :old_price, :new_price, keyword_init: true) do
      def kind
        return :new_plan if old_price.nil?

        new_price > old_price ? :increase : :decrease
      end

      def to_s
        old = old_price ? format("%.2f €", old_price) : "—"
        format("%-14s %8s → %.2f €  (%s)", plan, old, new_price, kind)
      end
    end

    def initialize(watched_plans)
      @watched = watched_plans.map(&:to_s)
    end

    def call(current, observed)
      @watched.filter_map do |plan|
        new_price = observed[plan]
        next if new_price.nil?                       # nun liggiuto: l'Extractor l'ha già sgammato

        old_price = current[plan]
        next if old_price && (old_price - new_price).abs < 0.005

        Change.new(plan: plan, old_price: old_price, new_price: new_price)
      end
    end
  end
end
