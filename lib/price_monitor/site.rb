# frozen_string_literal: true

module PriceMonitor
  # Il sito è una pagina statica: il template in site/index.html con i dati
  # incorporati, così si apre anche da file e si pubblica su qualunque hosting.
  module Site
    # render(template, "HISTORY_JSON" => json, "MARGHERITA_JSON" => json)
    # sostituisce ogni segnaposto <!-- NOME --> con il JSON corrispondente.
    def self.render(template, data)
      data.reduce(template) do |html, (name, json)|
        placeholder = "<!-- #{name} -->"
        raise "Segnaposto #{placeholder} non trovato nel template" unless html.include?(placeholder)

        # "</" dentro un <script> chiuderebbe il tag: lo si scrive "<\/", che in JSON è identico
        compact = JSON.generate(JSON.parse(json)).gsub("</", "<\\/")
        html.sub(placeholder) { compact }
      end
    end
  end
end
