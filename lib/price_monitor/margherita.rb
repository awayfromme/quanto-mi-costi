# frozen_string_literal: true

require "csv"

module PriceMonitor
  # Indice Margherita: 'o prezzo 'e na margherita pe' città e pe' mese, d' 'e
  # segnalaziune d' 'a gente appruvate a mano. Maje d' 'e app d' 'e consegne.
  module Margherita
    NATIONAL = "Italia"

    def self.config
      YAML.safe_load_file(PriceMonitor.path("config", "margherita.yml"))
    end

    # 'A stessa pizzeria scritta 'n modo diverso se conta na vota sola.
    def self.pizzeria_key(report)
      [report["city"], report["pizzeria"]].map { |s| s.downcase.squeeze(" ").strip }.join("|")
    end

    # data/margherita.json: 'e segnalaziune appruvate. Comme 'o storico
    # d' 'e abbonamente, se tocca sulo cu bin/approve.
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

    # Pe' ogni città e mese: 'a mediana d' 'e prezze, cu na segnalazione sola
    # pe' pizzeria ('a cchiù fresca d' 'o mese). 'A mediana regge meglio d' 'a
    # media quanno arriva nu prezzo sbagliato. Nu mese conta sulo cu almeno
    # `min_pizzerias` pizzerie diverse; "Italia" mette nzieme tutte 'e città.
    class Index
      def initialize(reports, min_pizzerias: 3)
        @reports = reports
        @min = min_pizzerias
      end

      # Esce accussì: { "Napoli" => { "2026-10" => { "median" => 6.5, "pizzerias" => 4 } } }
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

      # L'urdemo mese buono 'e ogni città e 'o cunfronto cu 'o stesso mese
      # 'e ll'anno primma, si pure chillo è buono.
      def latest
        monthly.to_h do |city, months|
          month, cur = months.max_by(&:first)
          year_ago = months[format("%04d-%s", month[0, 4].to_i - 1, month[5, 2])]
          row = cur.merge("month" => month)
          row["year_ago"] = year_ago["median"] if year_ago
          [city, row]
        end
      end

      # Appunì: 'o dato 'e tutta Italia nun tene cunfronto cu ll'anno primma.
      # N'anno fa 'e città erano ate, e 'a differenza misurarria chesto, no 'e prezze.
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

    # Fa addiventà l'export CSV d' 'o modulo segnalaziune da ricuntrollà. Niente
    # 'e "furbo": na riga ca nun torna se jetta cu 'o pecché, e si serve
    # s'aggiusta a mano dint' 'o file pending.
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

      # Liegge 'o prezzo: "6,50", "6.5 €", "€ 7" → 6.5, 6.5, 7.0
      def parse_price(str)
        m = str.match(/(\d{1,2})(?:[.,](\d{1,2}))?/) or return nil
        "#{m[1]}.#{m[2] || 0}".to_f.round(2)
      end

      # Maiuscole a posto: "reggio emilia" → "Reggio Emilia", "l'aquila" → "L'Aquila"
      def city_name(str)
        str.squeeze(" ").downcase.gsub(/(\A|[\s'’-])(\p{L})/) { "#{Regexp.last_match(1)}#{Regexp.last_match(2).upcase}" }
      end
    end
  end
end
