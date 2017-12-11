# kbremote

kbremote is a [Kiosk Browser Remote API](https://kioskbrowser.userecho.com/forums/2-knowledge-base/topics/100-how-to-use-the-rest-api/) client for Ruby.

## Installation
```
gem install kbremote
```

## Usage

```ruby

api = KbRemote::API.new(key: "YOUR_KB_API_KEY", secret: "YOUR_KB_API_SECRET")
device = api.devices.first
api.patch_device(device[:id], name: device[:name] + ' AAA')
```

## License
The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).
