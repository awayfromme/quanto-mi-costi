# frozen_string_literal: true

module PriceMonitor
  # Confronta i prezzi appena letti con il listino attuale dello storico.
  # Considera solo i piani che il monitor sa leggere (quelli in config):
  # i piani annuali o storici presenti solo nello storico vengono ignorati.
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
        next if new_price.nil?                       # non letto: già segnalato dall'Extractor

        old_price = current[plan]
        next if old_price && (old_price - new_price).abs < 0.005

        Change.new(plan: plan, old_price: old_price, new_price: new_price)
      end
    end
  end
end
