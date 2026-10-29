# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require_relative "../lib/price_monitor"

FIXTURES = File.join(__dir__, "fixtures")

class ExtractorTest < Minitest::Test
  def config(name) = PriceMonitor.services_config.fetch(name).fetch("plans")

  def test_reads_prices_on_same_line_and_on_following_lines
    text = File.read(File.join(FIXTURES, "netflix.txt"))
    result = PriceMonitor::Extractor.new(config("netflix")).call(text)

    assert result.ok?, result.errors.inspect
    assert_equal({ "base_ads" => 6.99, "standard" => 13.99, "premium" => 19.99 }, result.prices)
  end

  def test_standard_is_not_confused_with_standard_with_ads
    text = "Standard con pubblicità\n6,99 €\nStandard\n13,99 €\nPremium\n19,99 €"
    result = PriceMonitor::Extractor.new(config("netflix")).call(text)

    assert_equal 6.99, result.prices["base_ads"]
    assert_equal 13.99, result.prices["standard"]
  end

  def test_handles_euro_sign_before_price_and_non_breaking_space
    text = "Premium\n€ 15,99/mese"
    cfg = { "premium" => { "match" => "^premium", "min" => 5, "max" => 30 } }

    assert_equal 15.99, PriceMonitor::Extractor.new(cfg).call(text).prices["premium"]
  end

  def test_out_of_range_price_is_an_error_not_a_price
    text = "Premium\n199,99 €"
    cfg = { "premium" => { "match" => "^premium", "min" => 5, "max" => 30 } }
    result = PriceMonitor::Extractor.new(cfg).call(text)

    refute result.ok?
    assert_empty result.prices
  end

  def test_missing_plan_is_reported
    result = PriceMonitor::Extractor.new(config("netflix")).call("Pagina in manutenzione")

    assert_equal 3, result.errors.size
  end

  # Testo vero delle pagine in config/services.yml, letto da IP italiano il
  # 2026-10-29: i prezzi estratti devono coincidere con lo storico a quella data.
  %w[netflix spotify disney_plus].each do |name|
    define_method("test_real_#{name}_page_matches_history") do
      text = File.read(File.join(FIXTURES, "#{name}_reale.txt"))
      result = PriceMonitor::Extractor.new(config(name)).call(text)
      expected = PriceMonitor::History.load.prices_at(name, "2026-10-29").slice(*config(name).keys)

      assert result.ok?, result.errors.inspect
      assert_equal expected, result.prices
    end
  end
end

class HistoryTest < Minitest::Test
  def history = @history ||= PriceMonitor::History.load

  def test_netflix_launch_prices
    assert_equal({ "base" => 7.99, "standard" => 9.99, "premium" => 11.99 },
                 history.prices_at("netflix", "2015-10-22"))
  end

  def test_nothing_before_launch
    assert_empty history.prices_at("disney_plus", "2020-03-23")
  end

  def test_removed_plan_disappears
    assert history.prices_at("netflix", "2023-10-08").key?("base")
    refute history.prices_at("netflix", "2023-10-09").key?("base")
  end

  def test_current_listini
    assert_equal({ "base_ads" => 6.99, "standard" => 13.99, "premium" => 19.99 },
                 history.prices_at("netflix", "2026-10-29"))
    assert_equal 11.99, history.prices_at("spotify", "2026-10-29")["premium"]
    assert_equal 15.99, history.prices_at("disney_plus", "2026-10-29")["premium"]
  end

  def test_every_event_has_a_source_and_a_valid_date
    history.services.each do |id|
      history.events(id).each do |ev|
        Date.iso8601(ev["date"])
        refute_empty ev["sources"], "#{id} #{ev['date']} senza fonti"
      end
    end
  end

  def test_append_event_keeps_order_and_persists
    Dir.mktmpdir do |dir|
      path = File.join(dir, "history.json")
      File.write(path, File.read(PriceMonitor.path("data", "history.json"), encoding: "UTF-8"))
      h = PriceMonitor::History.load(path)
      h.append_event!("spotify", { "date" => "2026-11-01", "type" => "increase",
                                   "prices" => { "premium" => 12.99 }, "sources" => ["x"] })

      reloaded = PriceMonitor::History.load(path)
      assert_equal 12.99, reloaded.prices_at("spotify", "2026-11-01")["premium"]
      assert_equal "2026-11-01", reloaded.events("spotify").last["date"]
    end
  end
end

class DifferTest < Minitest::Test
  def test_detects_increase_and_ignores_unchanged
    changes = PriceMonitor::Differ.new(%w[premium duo])
                                  .call({ "premium" => 11.99, "duo" => 16.99 },
                                        { "premium" => 12.99, "duo" => 16.99 })

    assert_equal 1, changes.size
    assert_equal :increase, changes.first.kind
  end

  def test_new_plan
    changes = PriceMonitor::Differ.new(%w[lite]).call({}, { "lite" => 5.99 })

    assert_equal :new_plan, changes.first.kind
  end

  def test_plan_not_read_is_not_a_change
    assert_empty PriceMonitor::Differ.new(%w[premium]).call({ "premium" => 11.99 }, {})
  end
end

class CalculatorTest < Minitest::Test
  def test_compares_today_with_the_past
    calc = PriceMonitor::Calculator.new(PriceMonitor::History.load)
    r = calc.compare([%w[netflix standard], %w[spotify premium]],
                     since: Date.new(2019, 1, 1), today: Date.new(2026, 10, 29))

    # 2019-01-01: Netflix Standard 10,99 + Spotify 9,99 = 20,98
    # oggi:       13,99 + 11,99 = 25,98  → +5 €/mese, +60 €/anno
    assert_equal 20.98, r[:monthly_then]
    assert_equal 25.98, r[:monthly_now]
    assert_equal 60.0, r[:yearly_delta]
  end

  def test_plan_that_did_not_exist_is_excluded_from_comparison
    calc = PriceMonitor::Calculator.new(PriceMonitor::History.load)
    r = calc.compare([%w[disney_plus premium]], since: Date.new(2019, 1, 1),
                                                today: Date.new(2026, 10, 29))

    assert_nil r[:lines].first.then_price
    assert_equal 0.0, r[:yearly_delta]
  end
end
