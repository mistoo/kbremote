# frozen_string_literal: true
require "date"
require "json"
require "tempfile"
#require "rest-client"
require_relative 'filegroup'
require_relative 'auth'

module KbRemote
  require 'rest-client'
  if ENV['KBREMOTE_DEBUG'] == '1'
    def self.debug
      STDERR.puts "[KBREMOTE_DEBUG] #{yield}"
    end
  else
    def self.debug;end
  end

  class API
    BASE_URL = 'https://www.kbremote.net'
    API_URI = '/api'

    class Error < Exception; end
    class NotFound < Error; end
    class Forbidden < Error; end

    PUSH_ACTIONS = {
      request_status: 1,
      update_info: 2, #2 = Update device info (information such as software version, Android version etc...)
      restart_app: 3,
      take_screenshot: 4, #device screenshot if Knox activated device (returned JSON includes Data & ImageURL value if available)**
      reload_url: 5,
      #6 = Open WiFi Settings
      identify_device: 7, #7 = Identify device (show message box)
      #8 = Force Download Profile
      #9 = Download Profile (will only update if change has been detected)
      screen_off: 10,
      screen_on: 11,
      #12 = Open Kiosk Browser Settings
      open_settings: 12,
      #13  =Open TeamViewer QuickSupport or TeamViewer Host (if installed)
      open_teamviewer: 13,
      #14 = Exit Kiosk Browser
      exit_app: 14,
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

    def initialize(url: 'https://www.kbremote.net', key:, secret:)
      raise ArgumentError, "url must be set" unless url
      raise ArgumentError, "key must be set" unless key
      raise ArgumentError, "secret must be set" unless secret

      @api_url = url
      @api_key = key
      @api_secret = secret
      @uri = URI.parse(@api_url)
    end

    def api_path(method_name)
      method_name.to_s.split('_').collect{ |s| s.capitalize!; s }.join
    end

    def parse_response(re, akey = nil)
      if re.is_a?(Array)
        re.collect!{ |e| parse_response(e) }
      elsif re.is_a?(String) && (akey == :lastContacted || akey == :created)
        ts = "#{re} #{Time.now.getlocal.zone}" # add timezone as KB API gives localtime w/o tz
        re = DateTime.parse(ts)
      elsif re.is_a?(Hash)
        o = {}
        re.each do |key, value|
          if key.upcase == key
            key = key.downcase.to_sym
          else
            key = "#{key[0].downcase}#{key[1..-1]}".to_sym
          end
          value = parse_response(value, key)
          o[key] = value
        end
        re = o
      end
      re
    end

    def request(meth, path = nil, query: nil, body: nil, headers: nil, as_json: true)
      path = api_path(caller_locations(1,1)[0].label) if path.nil?
      path = "#{API_URI}/#{path}"

      headers = KbRemote::Auth.headers(meth, path, api_key: @api_key, api_secret: @api_secret)
      headers[:accept] = :json
      if body && as_json && body.is_a?(Hash)
        headers[:content_type] = :json
        body = JSON.generate(body)
      end
      headers[:params] = query if query # RestClient inconsitency

      KbRemote.debug{ "#{meth.upcase} #{path}" }
      KbRemote.debug{ "BODY #{body}" } if body

      re = RestClient::Request.execute(method: meth, url: "#{@api_url}#{path}", payload: body, headers: headers)
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
      KbRemote.debug{ "#{meth.upcase} #{path} #{re.code}" }
      data = JSON.parse(re.body)
      KbRemote.debug{ "RESPONSE #{JSON.pretty_generate(data)}" }
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
      request(:patch, "device/#{id}", body: data)
    end

    def take_screenshot(device_id)
      ano = PUSH_ACTIONS[:take_screenshot]

      re = request(:get, "push/#{device_id}/#{ano}")
      unless re[:data]
        nil
      else
        data = JSON.parse(re[:data], :symbolize_names => true)
        sleep 10
        if data[:ImageUrl]
          download_screenshot(device_id, data[:ImageUrl])
        else
          nil
        end
      end
    end

    def download_screenshot(device_id, url)
      re = RestClient::Request.execute(method: :get, url: url)
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
      path = Dir.tmpdir() + "/kbremote-screenshot-#{device_id}.jpg"
      File.open(path, "wb") do |file|
        file.write(re.body)
      end
      path
    end
    private :download_screenshot

    def device_push(device_id, action)
      raise ArgumentError, "#{action}: use take_screenshot method" if action == :take_screenshot

      ano = PUSH_ACTIONS[action]
      raise ArgumentError, "#{action}: no such action" unless ano
      re = request(:get, "push/#{device_id}/#{ano}")
      re && re[:pushed]
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

    # {\"templateprofileid\":1,\"name\":\"My Profile\",\"description\":\"My Profile Description\"}
    def create_profile(name, template_profile_id:, description: nil)
      body = {
        name: name,
        templateprofileid: template_profile_id,
        description: description
      }
      re = request(:post, "profile", :body => body)
      re && re[:created] ? re[:id] : nil
    end

    def patch_profile(id, kioskurl: nil, filegroup_id: nil)
      props = [ :kioskurl, :filegroup_id ]
      data = {}
      b = binding
      props.each do |prop|
        val = b.local_variable_get(prop)
        data[prop] = val unless val.nil?
      end
      raise ArgumentError, "need at least one of #{props.join(', ')}" if props.size.zero?
      re = request(:patch, "profile/#{id}", body: data)
      re && re[:updated] == true
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

    #{\"devicegroupid\":1,\"notes\":\"My notes\"}
    def registration_keys
      request(:get, "registrationkey")
    end
  end
end
