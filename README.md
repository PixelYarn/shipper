# Ship Cheap

This is a simple tool to make shipping easy for a home business.

## Usage

- Get a set of [EasyPost](https://www.easypost.com/) API keys
- Create a [.env](https://github.com/bkeepers/dotenv) file and set your `EASYPOST_TEST_KEY` and `EASYPOST_PROD_KEY`
- edit the shipping config file to describe the package you want to send
- from a terminal run `./ship_cheap -f shipping_config` to check the package cost
- from a terminal run `./ship_cheap -f shipping_config --buy` to buy postage and get a link to a shipping label
