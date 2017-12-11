# frozen_string_literal: true
require "date"
require "json"
require "rest-client"

require_relative 'filegroup'
module KbRemote
  class API
    BASE_URL = 'https://www.kbremote.net'
    API_URI = '/api'

    class Error < Exception; end
    class NotFound < Error; end
    class Forbidden < Error; end

    #include HTTParty
    #base_uri BASE_URL
    #debug_output $stderr

    PUSH_ACTIONS = {
      request_status: 1,
      #2 = Update device info (information such as software version, Android version etc...)
      restart_app: 3,
      take_screenshot: 4, #device screenshot if Knox activated device (returned JSON includes Data & ImageURL value if available)**
      reload_url: 5,
      #6 = Open WiFi Settings
      #7 = Identify device (show message box)
      #8 = Force Download Profile
      #9 = Download Profile (will only update if change has been detected)
      screen_off: 10,
      screen_on: 11,
      #12 = Open Kiosk Browser Settings
      #13 = Open TeamViewer QuickSupport or TeamViewer Host (if installed)
      #14 = Exit Kiosk Browser
      clear_cache_reload_url: 15,
      #15 = Clear WebView Cache and reload Kiosk Url
      #16 = Clear WebView Cookies and reload Kiosk Url
      #17 = Clear WebView Forms and reload Kiosk Url
      #18 = Clear WebView Cache, Cookies & Forms and reload Kiosk Url
      #19 = Upload device events data (for reporting), by default this occurs every 24 hours
      #20 = Upload device session data (for reporting), by default this occurs every 24 hours
      #21 = Clear WebView HTML5 WebStorage
      regain_focus: 23
    }

    def initialize(url: 'https://www.kbremote.net', key:, secret:, debug: false)
      raise ArgumentError, "url must be set" unless url
      raise ArgumentError, "key must be set" unless key
      raise ArgumentError, "secret must be set" unless secret

      @api_url = url
      @api_key = key
      @api_secret = secret
      @uri = URI.parse(@api_url)
      @debug = debug
    end

    def api_path(method_name)
      method_name.to_s.split('_').collect{ |s| s.capitalize!; s }.join
    end

    def parse_response(re)
      if re.is_a?(Array)
        re.collect!{ |e| parse_response(e) }

      elsif re.is_a?(Hash)
        o = {}
        re.each do |key, value|
          key = "#{key[0].downcase}#{key[1..-1]}".to_sym
          value = parse_response(value)
          o[key] = value
        end
        re = o
      elsif re.is_a?(String) && (key == :lastContacted || key == :created)
        #re = DateTime.parse(re)
      end
      re
    end

    def request(meth, path = nil, query: nil, body: nil, headers: nil, as_json: true)
      path = api_path(caller_locations(1,1)[0].label) if path.nil?
      path = "#{API_URI}/#{path}"

      headers = KbRemote::Auth.headers(meth, path, api_key: @api_key, api_secret: @api_secret)
      headers[:accept] = :json
      headers[:content_type] = :json if body && as_json && body.is_a?(Hash)
      headers[:params] = query if query # RestClient inconsitency

      re = RestClient::Request.execute(method: meth, url: "#{@api_url}#{path}", payload: body, headers: headers)
      #re = self.class.send(meth, path, options)
      if re.code != 200
        case re.code
        when 404
          raise NotFound, "#{re.code}"
        when 403
          raise Forbidden, "#{re.code}"
        else
          raise Error, "#{re.code}"
        end
      end
      #JSON.parse(re.body)
      data = JSON.parse(re.body)
      parse_response(data)
    rescue RestClient::TooManyRequests
      if as_json                # not multipart
        sleep 1
        request(meth, path, query: query, body: body, headers: headers, as_json: as_json)
      else
        raise
      end
    end

    def devices
      request(:get, 'device')
    end

    def device(id)
      request(:get, "device/#{id}")
    end

    # Properties: devicegroupid (int), name (string), updateoverrideurl (bool), overrideurl (string)
    def patch_device(id, name: nil, devicegroupid: nil, updateoverrideurl: nil, overrideurl: nil)
      props = [ :name, :devicegroupid, :updateoverrideurl, :overrideurl ]
      data = {}
      b = binding
      props.each do |prop|
        val = b.local_variable_get(prop)
        data[prop] = val unless val.nil?
      end
      raise ArgumentError, "need at least one of #{props.join(', ')}" if props.size.zero?
      puts data.inspect
      request(:patch, "device/#{id}", body: data)
    end

    def device_push(id, action)
      ano = PUSH_ACTIONS[action]
      raise ArgumentError, "#{action}: no such action" unless ano
      request(:get, "push/#{id}/#{ano}")
    end

    def device_groups
      request(:get, 'devicegroup')
    end

    def device_group(id)
      request(:get, "devicegroup/#{id}")
    end

    def create_device_group(name, profile_id:, create_registration_key: true)
      body = {
        name: name,
        profileid: profile_id,
        createregistrationkey: create_registration_key
      }
      re = request(:post, "devicegroup", :body => body)
      # response { created: true, id: 7620, registrationkey: 5e8c1430-36cf-4c9f-89c0-6c961ae23f37 }
      re
    end

    def profiles
      request(:get, "profile")
    end

    def profile(id)
      request(:get, "profile/#{id}")
    end

    def patch_profile(id, kioskurl:)
      request(:patch, "profile/#{id}", body: { kioskurl: kioskurl })
    end

    def filegroups
      request(:get, "filegroup").map{ |g| FileGroup.new(self, g) }
    end

    def filegroup(id)
      FileGroup.load(self, id)
    end

    def create_filegroup(name)
      FileGroup.create(self, name)
    end
  end
end