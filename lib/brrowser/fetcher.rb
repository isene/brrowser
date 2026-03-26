require 'net/http'
require 'uri'
require 'openssl'
require 'yaml'

module Brrowser
  class Fetcher
    MAX_REDIRECTS = 10
    TIMEOUT       = 15
    USER_AGENT    = "brrowser/0.1 (terminal browser)"
    COOKIE_FILE   = File.join(Dir.home, ".brrowser", "cookies.yml")

    def initialize
      @cookies = load_cookies
    end

    def fetch(url, method: :get, params: nil)
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
        if method == :post && params
          req = Net::HTTP::Post.new(path)
          req.set_form_data(params)
        else
          req = Net::HTTP::Get.new(path)
        end
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
          ct = response["content-type"] || ""
          body = response.body
          body = body.force_encoding("UTF-8") if ct.match?(/text|html|json|xml/)
          return {
            body:         body,
            url:          uri.to_s,
            content_type: ct,
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
      save_cookies
    end

    def cookies_for(uri)
      return "" unless @cookies[uri.host]
      @cookies[uri.host].map { |k, v| "#{k}=#{v}" }.join("; ")
    end

    def load_cookies
      return {} unless File.exist?(COOKIE_FILE)
      YAML.safe_load(File.read(COOKIE_FILE), permitted_classes: [Symbol]) rescue {}
    end

    def save_cookies
      dir = File.dirname(COOKIE_FILE)
      Dir.mkdir(dir) unless Dir.exist?(dir)
      File.write(COOKIE_FILE, @cookies.to_yaml)
    end
  end
end
