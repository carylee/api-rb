require 'httparty'
require 'json'
require 'digest/md5'

module OutsideIn
  module Resource
    # The base class for API resources.
    #
    # Resources are exposed by the API service at particular endpoints identified by URLs. Consumers can interact
    # with resources via the HTTP uniform interface.
    #
    # @example
    #   resource = new MyResource("/an/endpoint")
    #   data = resource.GET({'publication-id' => 1234, 'limit' => 5})
    #
    # @abstract Subclass and override {#scope} and {#params} to implement a custom resource class.
    # @since 1.0
    class Base
      # Returns a version of +url+ that includes publication scoping when +inputs+ contains a non-nil
      # +publication-id+ entry.
      #
      # @param [String] url the URL
      # @param [Hash<String, Object>] inputs the data inputs
      # @return [String] the potentially scoped URL
      # @since 1.0
      def self.scope(url, inputs)
        raise NotImplementedError
      end

      # Returns a version of +url+ with parameters in the query string corresponding to +inputs+.
      #
      # @param [String] url the URL
      # @param [Hash<String, Object>] inputs the data inputs
      # @return [String] the URL including query parameters
      # @since 1.0
      def self.parameterize(url, inputs)
        raise NotImplementedError
      end

      # Returns the signed form of +url+. Signing adds the +dev_key+ and +sig+ query parameters to the query string.
      #
      # @param [String] url a URL to be signed
      # @return [String] the signed URL
      # @raise [OutsideIn::SignatureException] if the key or secret are not set
      # @since 1.0
      def self.sign(url)
        raise SignatureException, "Key not set" unless OutsideIn.key
        raise SignatureException, "Secret not set" unless OutsideIn.secret
        sig_params = "dev_key=#{OutsideIn.key}&sig=#{self.make_auth_string}"
        url =~ /\?/ ? "#{url}&#{sig_params}" : "#{url}?#{sig_params}"
      end

      # Builds the auth string that is used in the API call
      #
      # @return [String] the auth string for the query parameter
      #
      def self.make_auth_string()
        raise SignatureException, "Key not set" unless OutsideIn.key
        raise SignatureException, "Secret not set" unless OutsideIn.secret
        hash = Digest::MD5.hexdigest(OutsideIn.key + OutsideIn.secret + Time.now.to_i.to_s)
      end

      # Returns a new instance. Stores the absolutized, signed URL.
      #
      # @param [String] relative_url a URL relative to the version component of the base service URL
      # @return [OutsideIn::Resource::Base]
      def initialize(relative_url)
        @url = "http://#{HOST}/v#{VERSION}#{relative_url}"
      end

      # Calls +GET+ on the remote API service and returns the data encapsulated in the response. The URL that is
      # called is created by scoping and parameterizing the canonical resource URL based on +inputs+.
      #
      # @param [Hash<String, Object>] inputs the data inputs
      # @return [Object] the returned data structure as defined by the API specification (as parsed from the JSON
      #   envelope)
      # @raise [OutsideIn::ForbiddenException] for a +403+ response
      # @raise [OutsideIn::NotFoundException] for a +404+ response
      # @raise [OutsideIn::ServiceException] for any error response that indicates a service fault of some type
      # @raise [OutsideIn::QueryException] for any error response that indicates an invalid request or other client
      #   problem
      # @since 1.0
      def GET(inputs)
        url = self.class.sign(self.class.parameterize(self.class.scope(@url, inputs), inputs))
        OutsideIn.logger.debug("Requesting #{url}") if OutsideIn.logger
        response = HTTParty.get(url)
        unless response.code < 300
          raise ForbiddenException if response.code == 403
          raise NotFoundException if response.code == 404
          if response.headers.include?('x-mashery-error-code')
            raise ServiceException, response.headers['x-mashery-error-code']
          else
            raise QueryException.new(JSON[response.body])
          end
        end
        JSON[response.body]
      end
    end
  end
end
