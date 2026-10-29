# frozen_string_literal: true

module PriceMonitor
  # Lo storico è una lista di eventi per servizio. Il listino in una certa data
  # si ottiene "piegando" gli eventi fino a quella data: ogni evento sovrascrive
  # i prezzi dei piani che nomina, null = piano non più sottoscrivibile.
  class History
    attr_reader :data

    def self.load(path = PriceMonitor.path("data", "history.json"))
      new(JSON.parse(File.read(path, encoding: "UTF-8")), path)
    end

    def initialize(data, path = nil)
      @data = data
      @path = path
    end

    def services = data.fetch("services").keys

    def service(id) = data.fetch("services").fetch(id)

    def events(id)
      service(id).fetch("events").sort_by { |e| e.fetch("date") }
    end

    # Listino attivo per i nuovi abbonati alla data indicata.
    def prices_at(id, date = Date.today)
      date = Date.parse(date.to_s)
      events(id).each_with_object({}) do |ev, acc|
        break acc if Date.parse(ev.fetch("date")) > date

        ev.fetch("prices").each do |plan, price|
          price.nil? ? acc.delete(plan) : acc[plan] = price
        end
      end
    end

    # Listino di oggi. Esclude i piani che sappiamo dismessi ma senza una data
    # verificata (es. Spotify Unlimited): meglio un buco che un prezzo falso.
    def current(id)
      prices_at(id, Date.today).except(*service(id).fetch("discontinued_undated", []))
    end

    def label(id, plan) = service(id).fetch("plans").fetch(plan, plan)

    def append_event!(id, event)
      service(id).fetch("events") << event
      service(id)["events"] = events(id)
      data["meta"]["updated_at"] = Date.today.iso8601
      save!
    end

    def save!
      raise "History caricata senza path" unless @path

      File.write(@path, JSON.pretty_generate(data) + "\n")
    end
  end
end
