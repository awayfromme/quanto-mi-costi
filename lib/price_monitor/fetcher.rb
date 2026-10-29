# frozen_string_literal: true

require "ferrum"

module PriceMonitor
  # Apre la pagina con un Chrome headless vero (i prezzi spesso arrivano via
  # JavaScript) e restituisce il testo visibile, come lo legge una persona.
  class Fetcher
    USER_AGENT = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 " \
                 "(KHTML, like Gecko) Chrome/130.0 Safari/537.36"

    def initialize(timeout: 30)
      @timeout = timeout
    end

    def text(url, wait_for: "body")
      browser = Ferrum::Browser.new(
        headless: true,
        timeout: @timeout,
        browser_options: { "lang" => "it-IT", "no-sandbox" => nil }
      )
      browser.headers.set("User-Agent" => USER_AGENT, "Accept-Language" => "it-IT,it;q=0.9")
      browser.go_to(url)
      browser.network.wait_for_idle(timeout: @timeout)
      browser.at_css(wait_for) # fallisce in modo chiaro se la pagina non è quella attesa
      dismiss_cookie_banner(browser)
      browser.evaluate("document.body.innerText")
    ensure
      browser&.quit
    end

    private

    # Rifiuta i cookie non essenziali se c'è un banner standard (OneTrust & co.).
    # Se non lo trova pazienza: innerText legge comunque la pagina sotto.
    def dismiss_cookie_banner(browser)
      %w[#onetrust-reject-all-handler button[data-testid='reject-all']].each do |sel|
        node = browser.at_css(sel)
        next unless node

        node.click
        sleep 0.5
        break
      end
    rescue Ferrum::Error
      nil
    end
  end
end
