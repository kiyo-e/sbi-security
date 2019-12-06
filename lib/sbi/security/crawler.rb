module Sbi::Security
  class Crawler
    include Capybara::DSL

    TOP_PAGE = "https://site1.sbisec.co.jp/ETGate"

    Capybara.register_driver :headless_chromium do |app|
      options = { args: %w{headless disable-features=VizDisplayCompositor} }
      caps = Selenium::WebDriver::Remote::Capabilities.chrome(chromeOptions: options)
      Capybara::Selenium::Driver.new(app, browser: :chrome, desired_capabilities: caps)
    end

    Capybara.default_driver = :headless_chromium

    def initialize(user_id, password)
      @password = password
      login(user_id, password)
      @tabs = { "top": last_opend_tab_id }
    end

    def portfolio
      find("img[title='ポートフォリオ']").click

      stocks = all(:xpath, '//table[@width="100%"]/tbody/tr[@align="center"]')
      .select { |tr| tr.text.include? "詳細" }.each_with_index.map do |tr, i|

        if is_margin_trade?(tr)
          _, code_and_name, type, expire_date, _, count, value, price, price_ratio, price_ratio_percentage, profit, profit_percentage,
          total_value = tr.all("td").map { |td| td.text.gsub(/,/, "") }
        else
          _, code_and_name, _, count, value, price, price_ratio, price_ratio_percentage, profit, profit_percentage,
          total_value = tr.all("td").map { |td| td.text.gsub(/,/, "") }
        end


        PortfolioStock.new(
          code: code_and_name.split(" ").first,
          name: code_and_name.split(" ").last,
          count: count,
          value: value,
          price: price,
          price_ratio: empty_string_to_num(price_ratio).to_i,
          price_ratio_percentage: empty_string_to_num(price_ratio_percentage).to_f,
          profit: empty_string_to_num(profit).to_i,
          profit_percentage: empty_string_to_num(profit_percentage).to_f,
          total_value: total_value
        )
      end

      Portfolio.new(stocks)
    end

    def stocks(codes)
      Array(codes).inject({}) do |a, e|
        if @tabs[e]
          page.driver.browser.switch_to.window @tabs[e]
        else
          page.open_new_window
          @tabs[e] = page.driver.browser.window_handles.last
          page.driver.browser.switch_to.window @tabs[e]
          visit TOP_PAGE
          find(:xpath, "//input[@id='top_stock_sec']").set e
          find("img[title='株価検索']").click
        end

        a[e] = stock(e)
        a
      end
    end

    def stock(code)
      begin
        # SBI security has XHR for fetching information. Need to wait until page finish to emulate JavaScript.
        loop do
          if find(:xpath, "//td[@id='MTB0_0']/p/em/span[@class='fxx01']").text != "--"
            break
          end
          sleep 0.1
        end
      rescue Capybara::ElementNotFound
        retry
      end

      begin
        price_ratio, price_ratio_percentage = all(:xpath, "//td[@id='MTB0_1']/p/span").map { |td| td.text.gsub(/,/, "") }
        start_price, end_price, highest_price, total_stock, lowest_price, total_price = all(:xpath, "//table[@class='tbl690']/tbody/tr/td/p/span[@class='fm01']").map { |td| td.text.gsub(/,/, "") }

        order_books = all(:xpath, "//div[@class='itaTbl02']/table/tbody/tr").drop(1).map do |tr|
          sell_volume, price, buy_volume = tr.all(:xpath, "./td").map(&:text)

          OrderBook.new(
            volume: sell_volume.empty? ? buy_volume : sell_volume,
            price: price,
            type: sell_volume.empty? ? "buy" : "sell"
          )
        end

        Stock.new(
          code: code,
          name: find(:xpath, "//h3/span[@class='fxx01']").text,
          price: find(:xpath, "//td[@id='MTB0_0']/p/em/span[@class='fxx01']").text.gsub(/,/, ""),
          price_ratio: empty_string_to_num(price_ratio).to_i,
          price_ratio_percentage: empty_string_to_num(price_ratio_percentage).to_f,
          start_price: start_price.to_i,
          end_price: end_price,
          highest_price: highest_price.to_i,
          total_stock: total_stock.to_i,
          lowest_price: lowest_price.to_i,
          total_price: total_price.to_i * 1000,
          order_books: order_books
        )
      rescue Selenium::WebDriver::Error::StaleElementReferenceError
        retry
      end
    end

    def buy(code:, quantity:, price: nil)
      switch_or_open_tab(:trade) do
        find("img[title='取引']").click
      end

      find("#genK").click
      find("#shouryaku").click

      fill_in :stock_sec_code, with: code
      fill_in :input_quantity, with: quantity
      fill_in :trade_pwd, with: @password

      if price
        fill_in :input_price, with: price
      else
        choose "成行", match: :first
      end

      find("img[title='注文発注']").click
    end

    def margin_sell(code:, quantity:, price: nil, kubun: "制度")
      switch_or_open_tab(:trade) do
        find("img[title='取引']").click
      end

      find("#shinU").click
      find("#shouryaku").click

      fill_in :stock_sec_code, with: code
      fill_in :input_quantity, with: quantity
      fill_in :trade_pwd, with: @password

      if price
        fill_in :input_price, with: price
      else
        choose "成行", match: :first
      end

      choose kubun

      find("img[title='注文発注']").click
    end

    def general_margin_sell_stocks
      switch_or_open_tab("在庫") do
        find("img[title='国内株式']").click
        click_link "一般信用売り銘柄一覧"
        click_link "12月"
        within find(:xpath, "/HTML/BODY[1]/TABLE[1]/TBODY[1]/TR[1]/TD[1]/FORM[1]/DIV[1]/DIV[2]/DIV[2]") do
          click_link "200件" if has_link?('200件')
        end
      end

      all("table.md-l-utl-mt10 tbody tr").map do |tr|
        _, code, name, _, quantity, _, _, _, _, _, _, _ = tr.all(:xpath, "./td").map(&:text)
        MarginStock.new(code: code, name: name, quantity: quantity)
      end
    end

    def logined?
      page.driver.browser.switch_to.window @tabs[:top]
      visit TOP_PAGE
      !page.has_css?("#user_input")
    end

    private

    def login(user_id, password)
      visit TOP_PAGE
      fill_in :user_id, with: user_id
      fill_in :user_password, with: password
      find_button(class: "ov").click
    end

    def empty_string_to_num(string)
      string == "--" ? nil : string
    end

    def is_margin_trade?(tr)
      tr.all(:css, "td").count == 14
    end

    def last_opend_tab_id
      page.driver.browser.window_handles.last
    end

    def switch_or_open_tab(name)
      if @tabs[name]
        page.driver.browser.switch_to.window @tabs[name]
      else
        page.open_new_window
        @tabs[name] = page.driver.browser.window_handles.last
        page.driver.browser.switch_to.window @tabs[name]
        visit TOP_PAGE
      end

      if block_given?
        yield
      end
    end
  end
end
