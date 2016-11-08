require 'rest-client'
require 'comicvine/helpers'
require 'comicvine/version'
require 'comicvine/cv_list'
require 'comicvine/cv_object'
require 'cgi'

## Yard Doc generation stuff
# @!macro [new] raise.ResourceNotSupportedError
#   @raise [ResourceNotSupportedError] indicating the resource requested is not supported
# @!macro [new] raise.ComicVineAPIError
#   @raise [ComicVineAPIError] indicating the api request code recived

##
# Base ComicVine module, holds default api variables
#
module ComicVine
  # ComicVine api version (1.0)
  API_VERSION = '1.0'

  # Base ComicVine url
  API_URL = 'http://comicvine.gamespot.com/api'

  # ComicVine format (json)
  API_FORMAT = 'json'

  # Array of available resources
  API_RESOURCES = [:character, :characters, :chat, :chats, :concept, :concepts, :episode, :episodes, :issue, :issues,
                   :location, :locations, :movie, :movies, :object, :objects, :origin, :origins, :person, :people,
                   :power, :powers, :promo, :promos, :publisher, :publishers, :series, :series_list, :search, :story_arc,
                   :story_arcs, :team, :teams, :types, :video, :videos, :video_type, :video_types, :video_category,
                   :video_categories, :volume, :volumes]

  class API

    ##
    # Raised when a resource is not implemented on the current API
    #
    # Must be included in {ComicVine::API_RESOURCES}
    #
    # @since 0.1.0
    class ResourceNotSupportedError < ScriptError
    end


    ##
    # Raised when a ComicVine API error is encountered
    #
    # @since 0.1.0
    class ComicVineAPIError < ScriptError
    end

    # Hash containing ComicVine resource types and corresponding id values
    @@types = nil
    # Last time we pulled types from the API
    @@last_type_check = nil

    attr_accessor :api_key

    ##
    # @example
    #   ComicVine::API.new('18357f40df87fb4a4aa6bbbb27cd8ad1deb08d3e')
    # @since 0.1.0
    def initialize(api_key)
      self.api_key = api_key
    end

    ##
    # Makes request for the current api version
    #
    # @return [String]
    # @since 0.1.0
    def get_api_version
      _make_request(:characters, limit: 1)['version'].to_s
    end

    ##
    # Search ComicVine with the provided information
    # @example
    #   api.search(:volume, 'Avengers ', limit: 5)
    #
    # @param resource [Symbol] The symbol of the resource to query
    # @param query [String] The string to query
    # @param params [Hash] optional parameters to pass to CV API
    # @return [ComicVine::CVSearchList]
    # @since 0.1.0
    def search(resource, query, **params)

      options = {
          resources: resource.to_s,
          query: CGI::escape(query)
      }

      options.merge! params

      ComicVine::CVSearchList.new(_make_request(:search, options), resource, query)
    end

    ##
    # Returns comicvine type information
    #
    # @return [Hash]
    # @since 0.1.0
    def types
      if @@types.nil? || (@@last_type_check + (4 * 60 * 60)) < Time.now
        @@last_type_check = Time.now
        @@types = _make_request(:types)['results']
      end
      @@types
    end

    ##
    # Cycles through type hash to return the +resource+ hash of the matching the detail_resource_name
    # @example
    #   api.find_detail(:issue) #=> { "detail_resource_name": "issue", "list_resource_name": "issues", "id": 4000 }
    # @param resource [Symbol] The symbol of the resource to return
    # @return [Hash]
    # @since 0.1.0
    def find_detail(resource)
      types.find { |t| t['detail_resource_name'] == resource.to_s }
    end

    ##
    # Cycles through type hash to return the +resource+ hash of the matching the list_resource_name
    # @example
    #   api.find_list(:issues) #=> { "detail_resource_name": "issue", "list_resource_name": "issues", "id": 4000 }
    # @param resource [Symbol] The symbol of the resource to return
    # @return [Hash]
    # @since 0.1.0
    def find_list(resource)
      types.find { |t| t['list_resource_name'] == resource.to_s }
    end

    ##
    # Fetches provided
    # @example
    #   api.get_list(:volumes, limit: 50)
    # @param resource [Symbol] The symbol of the resource to fetch (plural)
    # @param params [Hash] optional parameters to pass to CV API
    # @return [ComicVine::CVObjectList]
    # @since 0.1.0
    def get_list(resource, **params)
      resp = _make_request(resource, params)
      ComicVine::CVObjectList.new(resp, resource)
    end

    ##
    # Fetches provided +resource+ with associated +id+
    # @example
    #   api.get_details(:issue, '371103')
    # @param resource [Symbol] The symbol of the resource to fetch
    # @param id [String] The id of the resource you would like to fetch
    # @param params [Hash] optional parameters to pass to CV API
    # @return [ComicVine::CVObject]
    # @since 0.1.0
    def get_details(resource, id, **params)
      ops_hash = {
          id: id
      }
      ops_hash.merge! params
      resp = _make_request(resource, ops_hash)
      ComicVine::CVObject.new(resp['results'])
    end

    ##
    # Will fetch the provided +url+ as a ComicVine::CVObject
    # @example
    #   api.get_details_by_url("http://comicvine.gamespot.com/api/issue/4000-371103")
    # @param url [String]
    # @return [ComicVine::CVObject]
    def get_details_by_url(url)
      resp = _make_url_request(url)
      ComicVine::CVObject.new(resp['results'])
    end

    private

    ##
    # Builds api url string based on provided +resource+ and optional +id+
    #
    # @example Build a url for resource +:issue+ with an id of +371103+
    #   _build_base_url(:issue, '371103') #=> "http://comicvine.gamespot.com/api/issue/4000-371103"
    # @example Build a url for resource +:issues+
    #   _build_base_url(:issues) #=> "http://comicvine.gamespot.com/api/issues"
    #
    # @param resource [Symbol] The symbol of the resource to build the url for
    # @param id [String] optional id for specific resource requests
    # @return [String] Full url of the requested resource
    # @macro raise.ResourceNotSupportedError
    def _build_base_url(resource, id = nil)
      if ComicVine::API_RESOURCES.include? resource
        if !id.nil?
          API_URL + '/' + resource.to_s + '/' + "#{self.find_detail(resource)['id']}-#{id.to_s}"
        else
          API_URL + '/' + resource.to_s
        end
      else
        raise ResourceNotSupportedError, resource.to_s + ' is not a supported resource'
      end
    end

    ##
    # Executes api request based on provided +resource+ and +params+
    #
    # @example Return 5 results from the +:characters+ resource
    #   _make_request(:characters, limit: 5)
    #
    # @param resource [Symbol] The symbol of the resource to fetch
    # @param params [Hash] The named key value pairs of query parameters
    # @return [Hash]
    # @since 0.1.0
    # @macro raise.ComicVineAPIError
    # @macro raise.ResourceNotSupportedError
    def _make_request(resource, **params)
      _make_url_request(_build_base_url(resource, params[:id] || nil), params)
    end

    ##
    # Executes api request based on provided +resource+ and +params+
    #
    # @example Make a simple request with +limit: 1+
    #   _make_url_request('http://comicvine.gamespot.com/api/issues', limit: 1)
    #
    # @param url [String] Request url
    # @param params [Hash] optional request parameters
    # @return [Hash]
    # @since 0.1.0
    # @macro raise.ComicVineAPIError
    def _make_url_request(url, **params)

      # Default options hash
      options = {
          params: {
              api_key: self.api_key,
              format: ComicVine::API_FORMAT
          }
      }

      options[:params].merge! params

      begin
        # Perform request
        request = RestClient.get(url, options)
      rescue RestClient::NotFound, Error => e
        raise ComicVineAPIError, e.message
      end

      case request.code
        when 200
          req = JSON.parse(request.body)
          if req['error'].eql?('OK')
            req
          else
            raise ComicVineAPIError, req['error']
          end
        when 420
          raise ComicVineAPIError, 'Recived a '+request.code+' http response: You\'ve been rate limited'
        else
          raise ComicVineAPIError, 'Recived a '+request.code+' http response'
      end
    end
  end

end