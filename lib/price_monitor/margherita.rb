# frozen_string_literal: true

require "csv"

module PriceMonitor
  # Indice Margherita: prezzo tipico della pizza margherita per città e mese,
  # dalle segnalazioni degli utenti approvate a mano. Mai dalle app di delivery.
  module Margherita
    NATIONAL = "Italia"

    def self.config
      YAML.safe_load_file(PriceMonitor.path("config", "margherita.yml"))
    end

    # La stessa pizzeria scritta in modi diversi conta una volta sola.
    def self.pizzeria_key(report)
      [report["city"], report["pizzeria"]].map { |s| s.downcase.squeeze(" ").strip }.join("|")
    end

    # data/margherita.json: le segnalazioni approvate. Come lo storico degli
    # abbonamenti, si modifica solo con bin/approve.
    class Store
      attr_reader :data

      def self.load(path = PriceMonitor.path("data", "margherita.json"))
        new(JSON.parse(File.read(path, encoding: "UTF-8")), path)
      end

      def initialize(data, path = nil)
        @data = data
        @path = path
      end

      def reports = data.fetch("reports")

      def ids = reports.map { |r| r["id"] }

      def append_reports!(new_reports)
        unsourced = new_reports.select { |r| Array(r["sources"]).empty? }.map { |r| r["id"] }
        raise "Segnalazioni senza fonte: #{unsourced.join(', ')}" unless unsourced.empty?

        dup = new_reports.map { |r| r["id"] } & ids
        raise "Segnalazioni già approvate: #{dup.join(', ')}" unless dup.empty?

        reports.concat(new_reports)
        reports.sort_by! { |r| [r["date"], r["id"]] }
        data["meta"]["updated_at"] = Date.today.iso8601
        save!
      end

      def save!
        raise "Margherita caricata senza path" unless @path

        File.write(@path, JSON.pretty_generate(data) + "\n")
      end
    end

    # Per ogni città e mese: mediana dei prezzi, con una sola segnalazione per
    # pizzeria (la più recente del mese). La mediana regge meglio della media
    # a un prezzo sbagliato. Un mese conta solo con almeno `min_pizzerias`
    # pizzerie diverse; "Italia" mette insieme tutte le città.
    class Index
      def initialize(reports, min_pizzerias: 3)
        @reports = reports
        @min = min_pizzerias
      end

      # { "Napoli" => { "2026-10" => { "median" => 6.5, "pizzerias" => 4 } } }
      def monthly
        groups = Hash.new { |h, k| h[k] = {} }
        @reports.sort_by { |r| r["date"] }.each do |r|
          month = r["date"][0, 7]
          key = Margherita.pizzeria_key(r)
          groups[[r["city"], month]][key] = r["price"]
          groups[[NATIONAL, month]][key] = r["price"]
        end

        groups.each_with_object(Hash.new { |h, k| h[k] = {} }) do |((city, month), prices), acc|
          next if prices.size < @min

          acc[city][month] = { "median" => median(prices.values), "pizzerias" => prices.size }
        end.transform_values { |months| months.sort.to_h }
      end

      # Ultimo mese valido di ogni città e confronto con lo stesso mese
      # dell'anno prima, se anche quello è valido.
      def latest
        monthly.to_h do |city, months|
          month, cur = months.max_by(&:first)
          year_ago = months[format("%04d-%s", month[0, 4].to_i - 1, month[5, 2])]
          row = cur.merge("month" => month)
          row["year_ago"] = year_ago["median"] if year_ago
          [city, row]
        end
      end

      # Il dato nazionale non ha confronto annuale: un anno fa le città
      # coperte erano altre, e la differenza misurerebbe quello, non i prezzi.
      def to_site(form_url: "")
        rows = latest
        {
          "form_url" => form_url.to_s,
          "min_pizzerias" => @min,
          "reports" => @reports.size,
          "national" => rows.delete(NATIONAL)&.except("year_ago"),
          "cities" => rows.map { |city, row| row.merge("city" => city) }
                          .sort_by { |row| [-row["median"], row["city"]] },
          "monthly" => monthly
        }
      end

      private

      def median(values)
        v = values.sort
        mid = v.size / 2
        (v.size.odd? ? v[mid] : (v[mid - 1] + v[mid]) / 2.0).round(2)
      end
    end

    # Trasforma l'export CSV del modulo in segnalazioni da rivedere. Nessuna
    # interpretazione "furba": una riga che non torna viene scartata con il
    # motivo, e se serve la si corregge a mano nel file pending.
    class Import
      Result = Struct.new(:reports, :rejected, :photos, keyword_init: true)

      def initialize(config)
        @cols = config.fetch("columns")
        @min = config.fetch("min", 2)
        @max = config.fetch("max", 25)
      end

      def call(csv_text, known_ids: [], today: Date.today)
        result = Result.new(reports: [], rejected: [], photos: {})
        seen = known_ids.dup

        CSV.parse(csv_text, headers: true).each.with_index(2) do |row, line|
          report, photo, error = parse(row, today)
          if error
            result.rejected << "riga #{line}: #{error}"
          elsif seen.include?(report["id"])
            result.rejected << "riga #{line}: #{report['id']} già importata"
          else
            seen << report["id"]
            result.reports << report
            result.photos[report["id"]] = photo
          end
        end
        result
      end

      private

      def parse(row, today)
        get = ->(key) { row[@cols.fetch(key)].to_s.strip }

        id = get["id"]
        return [nil, nil, "manca l'ID della risposta"] if id.empty?

        city = city_name(get["city"])
        pizzeria = get["pizzeria"].squeeze(" ")
        return [nil, nil, "mancano città o pizzeria"] if city.empty? || pizzeria.empty?

        date = parse_date(get["date"])
        return [nil, nil, "data non valida (#{get['date']})"] unless date
        return [nil, nil, "data nel futuro (#{date})"] if date > today

        price = parse_price(get["price"])
        return [nil, nil, "prezzo non leggibile (#{get['price']})"] unless price
        return [nil, nil, "prezzo #{price} fuori range #{@min}-#{@max}"] unless price.between?(@min, @max)

        photo = get["photo"]
        return [nil, nil, "manca la foto del menu o dello scontrino"] unless photo.match?(%r{\Ahttps?://})

        report = { "id" => id, "date" => date.iso8601, "city" => city, "pizzeria" => pizzeria,
                   "price" => price, "sources" => ["modulo:#{id}"] }
        [report, photo, nil]
      end

      def parse_date(str)
        Date.iso8601(str)
      rescue Date::Error
        begin
          Date.strptime(str[0, 10], "%d/%m/%Y")
        rescue Date::Error
          nil
        end
      end

      # "6,50", "6.5 €", "€ 7" → 6.5, 6.5, 7.0
      def parse_price(str)
        m = str.match(/(\d{1,2})(?:[.,](\d{1,2}))?/) or return nil
        "#{m[1]}.#{m[2] || 0}".to_f.round(2)
      end

      # "reggio emilia" → "Reggio Emilia", "l'aquila" → "L'Aquila"
      def city_name(str)
        str.squeeze(" ").downcase.gsub(/(\A|[\s'’-])(\p{L})/) { "#{Regexp.last_match(1)}#{Regexp.last_match(2).upcase}" }
      end
    end
  end
end
