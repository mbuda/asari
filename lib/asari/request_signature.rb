require 'uri'
require 'digest'
require 'aws-sdk'

class Asari

  class RequestSignature

    AUTHORIZATION_HEADER_NAME = "Authorization"
    DATE_HEADER_NAME = "X-Amz-Date"

    def initialize(method, url, body = "")
      @method = method
      @uri = URI.parse(url)
      @body = body
      @now = Time.now.utc
      @access_key_id = AWS.config.credential_provider.credentials[:access_key_id]
      @access_key = AWS.config.credential_provider.credentials[:secret_access_key]
    end

    def signature
      k_date = OpenSSL::HMAC.digest('sha256', "AWS4" + @access_key, @now.strftime("%Y%m%d"))
      k_region = OpenSSL::HMAC.digest('sha256', k_date, aws_region)
      k_service = OpenSSL::HMAC.digest('sha256', k_region, "cloudsearch")
      k_signing = OpenSSL::HMAC.digest('sha256', k_service, "aws4_request")
      Digest.hexencode(OpenSSL::HMAC.digest('sha256', k_signing, string_to_sign))
    end

    def signature_headers
      header_value = "AWS4-HMAC-SHA256 Credential=#{@access_key_id}/#{credential_scope}, SignedHeaders=host, Signature=#{signature}"
      {
        AUTHORIZATION_HEADER_NAME => header_value,
        DATE_HEADER_NAME => @now.strftime("%Y%m%dT%H%M%SZ")
      }
    end

    private

    def canonical_request
      [
        @method,
        @uri.path,
        sorted_query,
        "host:#{@uri.host}\n",
        "host",
        Digest::SHA256.hexdigest(@body)
      ].join("\n")
    end

    def sorted_query
      sorted = @uri.query.to_s.split('&').map { |q| q.split("=") }.sort { |a,b| a[0] <=> b[0] }.map { |q| q.join("=") }.join("&")

      # There are some differences between escaped query params in AWS service and in URI module
      # from Ruby library.
      URI.escape(URI.unescape(sorted)).gsub("(","%28").gsub(')','%29').gsub('[','%5B').gsub(']','%5D').gsub(':','%3A').gsub("'",'%27').gsub(',','%2C')
    end

    def credential_scope
      "#{@now.strftime("%Y%m%d")}/#{aws_region}/cloudsearch/aws4_request"
    end

    def aws_region
      @uri.to_s.match(/\.(?<aws_region>.+)\.(?<aws_service>.+)\.amazonaws\.com/)[:aws_region]
    end

    def string_to_sign
      [
        "AWS4-HMAC-SHA256",
        @now.strftime("%Y%m%dT%H%M%SZ"),
        credential_scope,
        Digest::SHA256.hexdigest(canonical_request)
      ].join("\n")
    end

  end

end

