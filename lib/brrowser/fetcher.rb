require 'net/http'
require 'uri'
require 'openssl'

module Brrowser
  class Fetcher
    MAX_REDIRECTS = 10
    TIMEOUT       = 15
    USER_AGENT    = "brrowser/0.1 (terminal browser)"

    def initialize
      @cookies = {}
    end

    def fetch(url)
      url = "https://#{url}" unless url.match?(%r{^https?://})
      uri = URI.parse(url)
      redirects = 0

      loop do
        raise "Too many redirects" if redirects >= MAX_REDIRECTS

        http = Net::HTTP.new(uri.host, uri.port)
        http.open_timeout = TIMEOUT
        http.read_timeout = TIMEOUT
        if uri.scheme == "https"
          http.use_ssl = true
          http.verify_mode = OpenSSL::SSL::VERIFY_PEER
        end

        path = uri.request_uri.empty? ? "/" : uri.request_uri
        req = Net::HTTP::Get.new(path)
        req["User-Agent"]      = USER_AGENT
        req["Accept"]          = "text/html,application/xhtml+xml,*/*"
        req["Accept-Language"]  = "en-US,en;q=0.9"
        req["Accept-Encoding"] = "identity"
        cookie_str = cookies_for(uri)
        req["Cookie"] = cookie_str unless cookie_str.empty?

        response = http.request(req)
        store_cookies(uri, response)

        case response
        when Net::HTTPRedirection
          location = response["location"]
          uri = location.start_with?("http") ? URI.parse(location) : URI.join(uri, location)
          redirects += 1
        when Net::HTTPSuccess
          return {
            body:         response.body.force_encoding("UTF-8"),
            url:          uri.to_s,
            content_type: response["content-type"] || "",
            status:       response.code.to_i
          }
        else
          return {
            body:         "Error #{response.code}: #{response.message}",
            url:          uri.to_s,
            content_type: "text/plain",
            status:       response.code.to_i
          }
        end
      end
    rescue => e
      {
        body:         "Error: #{e.message}",
        url:          url,
        content_type: "text/plain",
        status:       0
      }
    end

    private

    def store_cookies(uri, response)
      Array(response.get_fields("set-cookie")).each do |raw|
        name_val = raw.split(";").first.strip
        name, val = name_val.split("=", 2)
        @cookies[uri.host] ||= {}
        @cookies[uri.host][name] = val
      end
    end

    def cookies_for(uri)
      return "" unless @cookies[uri.host]
      @cookies[uri.host].map { |k, v| "#{k}=#{v}" }.join("; ")
    end
  end
end
