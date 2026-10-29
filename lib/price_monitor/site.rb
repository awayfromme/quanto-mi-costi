# frozen_string_literal: true

module PriceMonitor
  # 'O sito è na paggena ferma: 'o template 'e site/index.html cu 'e date
  # 'a dinto, accussì s'arape pure da file e se mette ncopp' a qualunque hosting.
  module Site
    # render(template, "HISTORY_JSON" => json, "MARGHERITA_JSON" => json)
    # mette ô posto 'e ogni segnaposto <!-- NOME --> 'o JSON ca lle spetta.
    def self.render(template, data)
      data.reduce(template) do |html, (name, json)|
        placeholder = "<!-- #{name} -->"
        raise "Segnaposto #{placeholder} non trovato nel template" unless html.include?(placeholder)

        # Appunì: "</" dint' a nu <script> chiudarria 'o tag; se scrive "<\/", ca pe' JSON è 'a stessa cosa
        compact = JSON.generate(JSON.parse(json)).gsub("</", "<\\/")
        html.sub(placeholder) { compact }
      end
    end
  end
end
