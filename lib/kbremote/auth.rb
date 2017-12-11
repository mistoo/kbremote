require 'openssl'
require 'base64'

module KbRemote
  module Auth
    def self.hmac(meth, timestamp, uri, secret)
      m = "#{meth.to_s.upcase}#{timestamp}#{uri}"
      #puts m
      hash = OpenSSL::HMAC.digest('sha256', secret, m)
      sm = Base64.encode64(hash)
      sm
    end

    def self.headers(meth, uri, api_key:, api_secret:)
      ts = Time.now.utc.strftime('%Y-%m-%d %H:%M:%S')
      {
        "Authentication" => "#{api_key}:#{hmac(meth, ts, uri, api_secret)}",
        "Timestamp" => ts
      }
    end
  end
end
