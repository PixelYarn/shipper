#!/usr/bin/env ruby
require 'easypost'
require 'yaml'
require 'slop'
require 'toml-rb'

require 'dotenv'
Dotenv.load

opts = Slop.parse do |o|
  o.string '-f', '--file', 'a postage config file'
  o.bool '--buy', 'Actually buy the label'
  o.bool '--test', 'Use the testing environment'
  o.string '--service', 'the postal service level to use'
  o.int '--max-days', 'the maximum allowed days to deliver'
end

unless opts[:file]
  puts opts
  exit
end

if opts[:test]
  # Test Key
  EasyPost.api_key = ENV['EASYPOST_TEST_KEY']
else
  # LIVE KEY!!
  EasyPost.api_key = ENV['EASYPOST_PROD_KEY']
end

# Loads and provides access to the shipping config
class ShippingConfig
  attr_reader :from, :to, :package, :customs_info, :customs_items, :insurance

  def initialize(file)
    @config = YAML.load_file(file)
    File.open(file + '.toml', 'w') do |f|
      f.write(TomlRB.dump(@config))
    end
    @from = @config['from']
    @to = @config['to']
    @package = @config['package']
    @customs_info = @config['customs_info']
    @customs_items = @config['customs_items']
    @insurance = @config['insurance']
  end
end

# Checks the price for a shipment
class CheckPriceCommand
  def initialize(config, shipment, rate)
    @config = config
    @shipment = shipment
    @rate = rate
  end

  def run
    to_addr = @config.to

    puts "rate: #{@rate[:rate]}",
         "carrier: #{@rate[:carrier]}, #{@rate[:service]}",
         "insurance value (costs 1% of value insured): #{@config.insurance}"
  end
end

# Purchases Postage for a shipment
class PurchasePostageCommand
  def initialize(shipment, insurance_amount, rate)
    @shipment = shipment
    @insurance_amount = insurance_amount || 0
    @rate = rate
  end

  def run
    @shipment.buy(
      rate: @rate
    )
    @shipment.insure(amount: @insurance_amount) if @insurance_amount > 0

    @shipment.label('file_format' => 'pdf')
    puts "Tracking Code:    #{@shipment.tracking_code}",
         "Shipping Label:   #{@shipment.postage_label.label_pdf_url}",
         "Shipment ID Code: #{@shipment.id}"
  end
end

# Verifies and displays the address
class PrintAddressCommand
  def initialize(to_address)
    @to_address = to_address
  end

  # Print the verified destination
  def run
    verified = @to_address

    puts "#{verified.name || verified.company}",
         "#{verified.street1}",
         "#{verified.street2}",
         "#{verified.city}, #{verified.state} #{verified.zip}",
         ''
  end
end

shipping_config = ShippingConfig.new(opts[:file])

from_address = EasyPost::Address.create_and_verify(shipping_config.from)
to_address = EasyPost::Address.create(shipping_config.to)
to_address = to_address.verify if to_address.country == 'US'
parcel = EasyPost::Parcel.create(shipping_config.package)
insurance_amount = shipping_config.insurance

customs_form = unless shipping_config.customs_info.nil?
                 customs_items = if shipping_config.customs_items
                                   shipping_config.customs_items.map do |item|
                                     EasyPost::CustomsItem.create(item)
                                   end
                                 end
                 combined = shipping_config.customs_info
                 combined[:customs_items] = customs_items
                 EasyPost::CustomsInfo.create(combined)
               end
shipment = EasyPost::Shipment.create(
  to_address: to_address,
  from_address: from_address,
  parcel: parcel,
  customs_info: customs_form
)

selected_rate = if opts['service'] || opts['max-days']
                  rate_options = shipment.rates

                  rate_options = rate_options.select { |r| r.service == opts['service'] } if opts['service']
                  rate_options = rate_options.select { |r| r.delivery_days <= opts['max-days'] } if opts['max-days']

                  rate_options.min_by { |r| r.rate.to_f }
                else
                  shipment.lowest_rate
                end
fail unless selected_rate

PrintAddressCommand.new(to_address).run
if opts[:buy]
  PurchasePostageCommand.new(shipment, insurance_amount, selected_rate)
else
  CheckPriceCommand.new(shipping_config, shipment, selected_rate)
end.run
