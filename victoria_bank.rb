require 'watir'
require 'nokogiri'
require 'pry'
require 'json'
require 'rubocop'
require 'open-uri'
require_relative 'transactions.rb'
require_relative 'accounts.rb'

class Victoria_bank_md

	def get_user_credentials
		puts "Enter your username"
		@username = gets.chomp
		puts "Please enter your password"
		@password = gets.chomp
	end

	def set_user_credentials
		@browser.text_field(class:'username').set(@username)
		@browser.text_field(id:'password').set(@password)
		@browser.button(class:'wb-button').click

		validate_login
	end

	def validate_login
		Watir::Wait.until do
			if @browser.div(class: "error", text: "Invalid username or password").present?
 				puts "Inlavid username or password"
 				break
			end
			@browser.div(class:"contracts").present?
		end
	end

	def init_session
		@browser = Watir::Browser.new
		@browser.goto "https://web.vb24.md/wb/#login"
		Watir::Wait.until{ @browser.input(class:'username').present? }	
	end

	def run
		init_session
		get_user_credentials
		set_user_credentials
		access_accounts
		access_transactions
		sort
		export_to_json
	end

	def access_accounts
		divs = @browser.divs(class: 'main-info')
		@account_details = [ ]
		divs.each do |element|
			accounts_html = Nokogiri::HTML(element.html)
			parse_acc(accounts_html)
		end
		@account_details
	end

	def access_transactions
		@browser.a(class: 'menu-link').click
		sleep 0.5

		@account_details.each do |acc|
			@browser.a(class: 'chosen-single').click
			Watir::Wait.until{ @browser.span(class: 'contract-name', text: acc.name).present? }

			@browser.span(class: 'contract-name', text: acc.name).click
			sleep 1

			set_date

			next if @browser.h1(text: "No operations found").present?

			acc.transactions = get_trans
		end
	end

	def parse_acc(accounts_html)
		name     = accounts_html.at_css('a.name').text
		balance  = accounts_html.at_css('span.amount').text
		currency = accounts_html.at_css('span.currency').text
		accounts_html.css('div')[3].content.empty? ? nature = 'Account' : nature ='Card Account'
		account  = Accounts.new(name, currency, balance, nature)
		@account_details << account
	end

	def parse_transaction(transactions_html)
		description         = transactions_html.css('h1').text
		date                = Date.parse(transactions_html.css('div.value')[0].text).strftime
		amount              = transactions_html.at_css('span.amount').text
		transaction_details = Transactions.new(date, description, amount)		
		@transactions_details << transaction_details
	end

	def set_date
		day = Date.today.day.to_s
    @browser.input(name: 'from').click
    @browser.a(class: "ui-datepicker-prev ui-corner-all").click
    @browser.a(text: day).click

    Watir::Wait.until{ @browser.div(class: 'day-operations').present? || 
    	@browser.h1(text: "No operations found").present? }
	end

	def get_trans
		divs = @browser.divs(class: 'day-operations')
		@transactions_details = [ ]
		divs.each do |transactions|
			transactions.span(class: "history-item-description").links.each do |transaction|
				transaction.click
				sleep 1
				Watir::Wait.until{ @browser.div(id: 'operation-details-dialog').present? }
				sleep 1
				transactions_html = Nokogiri::HTML(@browser.div(id: 'operation-details-dialog').html)
				parse_transaction(transactions_html)
				@browser.send_keys :escape
			end
		end	
		@transactions_details
	end

	def sort
		final_hash = { }

		final_hash['accounts'] = @account_details.map do |account|
		  {
		    'name'         => account.name,
		    'balance'      => account.balance,
		    'currency'     => account.currency,
		    'nature'       => account.nature,
		    'transactions' => account.transactions.map do |transaction|
		    	next if transaction.nil?
		      {
		        'date'        => transaction.date,
		        'description' => transaction.description,
		        'amount'      => transaction.amount
		      }
		    end
		    }
		end
		
		final_hash
	end

	def export_to_json
    @file_name = 'banking_info.json'
    File.open("#{@file_name}", 'w') do |file|
      file.write(JSON.pretty_generate(sort))
    end
	end
end

Victoria_bank_md.new.run
