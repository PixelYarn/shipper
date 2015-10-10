#!/usr/bin/env ruby
require 'easypost'
require 'yaml'
require 'slop'

require 'dotenv'
Dotenv.load

opts = Slop.parse do |o|
  o.string '-f', '--file', 'a postage config file'
  o.bool '--buy', 'Actually buy the label'
  o.bool '--test', 'Use the testing environment'
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
  def initialize(config, shipment)
    @config = config
    @shipment = shipment
  end

  def run
    to_addr = @config.to
    lowest = @shipment.lowest_rate
    puts "rate: #{lowest[:rate]}",
         "carrier: #{lowest[:carrier]}",
         "insurance value (costs 1% of value insured): #{@config.insurance}"
  end
end

# Purchases Postage for a shipment
class PurchasePostageCommand
  def initialize(shipment, insurance_amount)
    @shipment = shipment
    @insurance_amount = insurance_amount
  end

  def run
    @shipment.buy(
      rate: @shipment.lowest_rate
    )
    p @shipment.insure(amount: @insurance_amount) if @insurance_amount > 0

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

PrintAddressCommand.new(to_address).run
if opts[:buy]
  PurchasePostageCommand.new(shipment, insurance_amount)
else
  CheckPriceCommand.new(shipping_config, shipment)
end.run
