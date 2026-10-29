# frozen_string_literal: true

module PriceMonitor
  # 'O storico è na lista d'evente pe' ogni servizio. 'O listino a na certa data
  # s'ottene "piegando" 'e evente fino a chella data: ogni evento se scrive
  # ncopp' 'e prezze d' 'e piane ca nomina, null = piano ca nun se pò cchiù fà.
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

    # 'O listino pe' chi s'abbona nuovo â data ca se dice.
    def prices_at(id, date = Date.today)
      date = Date.parse(date.to_s)
      events(id).each_with_object({}) do |ev, acc|
        break acc if Date.parse(ev.fetch("date")) > date

        ev.fetch("prices").each do |plan, price|
          price.nil? ? acc.delete(plan) : acc[plan] = price
        end
      end
    end

    # 'O listino 'e mo'. Lassa fore 'e piane ca sapimmo ca so' fernute ma senza
    # na data sicura (es. Spotify Unlimited): meglio nu pertuso ca nu prezzo fauzo.
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

    # Azzecca fonte (e si serve na nota nova) a n'evento ca già ce sta,
    # senza tuccà date e prezze: serve pe' quanno 'a conferma s'è sgammata doppo.
    def amend_event!(id, date, sources:, note: nil)
      matches = service(id).fetch("events").select { |e| e["date"] == date }
      raise "#{id}: #{matches.size} eventi in data #{date}, ne serve esattamente uno" unless matches.size == 1
      raise "Nessuna fonte da aggiungere" if Array(sources).empty?

      event = matches.first
      event["sources"] = (event.fetch("sources") + sources).uniq
      event["note"] = note if note
      data["meta"]["updated_at"] = Date.today.iso8601
      save!
      event
    end

    def save!
      raise "History caricata senza path" unless @path

      File.write(@path, JSON.pretty_generate(data) + "\n")
    end
  end
end
