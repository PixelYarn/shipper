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

shipping_config = YAML.load_file(opts[:file])

from_address = EasyPost::Address.create(shipping_config['from'])
to_address = EasyPost::Address.create(shipping_config['to'])
parcel = EasyPost::Parcel.create(shipping_config['package'])

shipment = EasyPost::Shipment.create(
  to_address: to_address,
  from_address: from_address,
  parcel: parcel
)

unless opts[:buy]
  to_addr = shipping_config['to']
  lowest = shipment.lowest_rate
  puts "to: #{to_addr['name']} in #{to_addr['city']}, #{to_addr['state']}",
       "rate: #{lowest[:rate]}",
       "carrier: #{lowest[:carrier]}"
  exit
end

shipment.buy(
  rate: shipment.lowest_rate
)
shipment.label('file_format' => 'pdf')

puts "Tracking Code:    #{shipment.tracking_code}"
puts "Shipping Label:   #{shipment.postage_label.label_pdf_url}"
puts "Shipment ID Code: #{shipment.id}"
