# frozen_string_literal: true

require "ferrum"

module PriceMonitor
  # Arape 'a paggena cu nu Chrome headless overo ('e prezze spisso arrivano
  # cu 'o JavaScript) e te torna 'o testo ca se vede, comme 'o legge na perzona.
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
      browser.at_css(wait_for) # si 'a paggena nun è chella ca aspettammo, se sgamma subbeto
      dismiss_cookie_banner(browser)
      browser.evaluate("document.body.innerText")
    ensure
      browser&.quit
    end

    private

    # Dice no ê cookie ca nun servono si ce sta nu banner normale (OneTrust & co.).
    # Si nun 'o trova, pacienza: innerText legge 'a paggena sotto 'o stesso.
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
