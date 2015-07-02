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
  attr_reader :from, :to, :package, :customs_info, :customs_items

  def initialize(file)
    @config = YAML.load_file(file)
    @from = @config['from']
    @to = @config['to']
    @package = @config['package']
    @customs_info = @config['customs_info']
    @customs_items = @config['customs_items']
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
    puts "to: #{to_addr['name']} in #{to_addr['city']}, #{to_addr['state']}",
         "rate: #{lowest[:rate]}",
         "carrier: #{lowest[:carrier]}"
  end
end

# Purchases Postage for a shipment
class PurchasePostageCommand
  def initialize(shipment)
    @shipment = shipment
  end

  def run
    @shipment.buy(
      rate: @shipment.lowest_rate
    )
    @shipment.label('file_format' => 'pdf')

    puts "Tracking Code:    #{@shipment.tracking_code}"
    puts "Shipping Label:   #{@shipment.postage_label.label_pdf_url}"
    puts "Shipment ID Code: #{@shipment.id}"
  end
end

shipping_config = ShippingConfig.new(opts[:file])

from_address = EasyPost::Address.create(shipping_config.from)
to_address = EasyPost::Address.create(shipping_config.to)
parcel = EasyPost::Parcel.create(shipping_config.package)

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

if opts[:buy]
  PurchasePostageCommand.new(shipment)
else
  CheckPriceCommand.new(shipping_config, shipment)
end.run
