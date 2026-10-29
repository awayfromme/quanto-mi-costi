# frozen_string_literal: true

module PriceMonitor
  # Il cuore di "Quanto mi costi": dato un elenco di abbonamenti
  # (servizio + piano) dice quanto costano oggi e quanto costavano a una
  # data passata, e quanto paghi in più all'anno.
  class Calculator
    Line = Struct.new(:service, :plan, :then_price, :now_price, keyword_init: true)

    def initialize(history)
      @history = history
    end

    # subs: [["netflix", "standard"], ["spotify", "premium"]]
    # Se un piano non esisteva alla data `since`, then_price resta nil
    # e quella riga non entra nel confronto.
    def compare(subs, since:, today: Date.today)
      lines = subs.map do |service, plan|
        Line.new(
          service: service,
          plan: plan,
          then_price: @history.prices_at(service, since)[plan],
          now_price: @history.prices_at(service, today)[plan]
        )
      end

      comparable = lines.select { |l| l.then_price && l.now_price }
      then_month = comparable.sum(&:then_price)
      now_month  = comparable.sum(&:now_price)

      {
        lines: lines,
        monthly_then: then_month.round(2),
        monthly_now: now_month.round(2),
        yearly_delta: ((now_month - then_month) * 12).round(2),
        pct: then_month.zero? ? nil : (((now_month / then_month) - 1) * 100).round(1)
      }
    end
  end
end
