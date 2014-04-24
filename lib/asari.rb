require "asari/version"

require "asari/collection"
require "asari/exceptions"
require "asari/geography"

require "httparty"

require "ostruct"
require "json"
require "cgi"

class Asari
  def self.mode
    @@mode
  end

  def self.mode=(mode)
    @@mode = mode
  end

  attr_writer :api_version
  attr_writer :search_domain
  attr_writer :aws_region

  def initialize(search_domain=nil, aws_region=nil)
    @search_domain = search_domain
    @aws_region = aws_region
  end

  # Public: returns the current search_domain, or raises a
  # MissingSearchDomainException.
  #
  def search_domain
    @search_domain || raise(MissingSearchDomainException.new)
  end

  # Public: returns the current api_version, or the sensible default of
  # "2011-02-01" (at the time of writing, the current version of the
  # CloudSearch API).
  #
  def api_version
    @api_version || "2013-01-01"
  end

  # Public: returns the current aws_region, or the sensible default of
  # "us-east-1."
  def aws_region
    @aws_region || "us-east-1"
  end

  # Public: Search for the specified term.
  #
  # Examples:
  #
  #     @asari.search("fritters") #=> ["13","28"]
  #     @asari.search(filter: { and: { type: 'donuts' }}) #=> ["13,"28","35","50"]
  #     @asari.search("fritters", filter: { and: { type: 'donuts' }}) #=> ["13"]
  #
  # Returns: An Asari::Collection containing all document IDs in the system that match the
  #   specified search term. If no results are found, an empty Asari::Collection is
  #   returned.
  #
  # Raises: SearchException if there's an issue communicating the request to
  #   the server.
  def search(term, options = {})
    return Asari::Collection.sandbox_fake if self.class.mode == :sandbox
    term,options = "",term if term.is_a?(Hash) and options.empty?

    bq = boolean_query(options[:filter]) if options[:filter]
    page_size = options[:page_size].nil? ? 10 : options[:page_size].to_i

    url = "http://search-#{search_domain}.#{aws_region}.cloudsearch.amazonaws.com/#{api_version}/search"
    url += "?q=#{CGI.escape(term.to_s)}"
    url += "&fq=#{bq}" if options[:filter]
    url << build_facets(options[:facet]) if options[:facet]
    url += "&size=#{page_size}"
    url += "&return=#{options[:return_fields].join(',')}" if options[:return_fields]

    if options[:page]
      start = (options[:page].to_i - 1) * page_size
      url << "&start=#{start}"
    end

    url << normalize_sort(options[:sort]) if options[:sort]

    begin
      response = HTTParty.get(url)
    rescue Exception => e
      ae = Asari::SearchException.new("#{e.class}: #{e.message} (#{url})")
      ae.set_backtrace e.backtrace
      raise ae
    end

    unless response.response.code == "200"
      raise Asari::SearchException.new("#{response.response.code}: #{response.response.msg} (#{url})")
    end

    Asari::Collection.new(response, page_size)
  end

  # Public: Add an item to the index with the given ID.
  #
  #     id - the ID to associate with this document
  #     fields - a hash of the data to associate with this document. This
  #       needs to match the search fields defined in your CloudSearch domain.
  #
  # Examples:
  #
  #     @asari.update_item("4", { :name => "Party Pooper", :email => ..., ... }) #=> nil
  #
  # Returns: nil if the request is successful.
  #
  # Raises: DocumentUpdateException if there's an issue communicating the
  #   request to the server.
  #
  def add_item(id, fields)
    return nil if self.class.mode == :sandbox
    query = { "type" => "add", "id" => id.to_s }
    fields.each do |k,v|
      fields[k] = convert_date_or_time(fields[k])
      fields[k] = "" if v.nil?
    end

    query["fields"] = fields
    doc_request(query)
  end

  # Public: Update an item in the index based on its document ID.
  #   Note: As of right now, this is the same method call in CloudSearch
  #   that's utilized for adding items. This method is here to provide a
  #   consistent interface in case that changes.
  #
  # Examples:
  #
  #     @asari.update_item("4", { :name => "Party Pooper", :email => ..., ... }) #=> nil
  #
  # Returns: nil if the request is successful.
  #
  # Raises: DocumentUpdateException if there's an issue communicating the
  #   request to the server.
  #
  def update_item(id, fields)
    add_item(id, fields)
  end

  # Public: Remove an item from the index based on its document ID.
  #
  # Examples:
  #
  #     @asari.search("fritters") #=> ["13","28"]
  #     @asari.remove_item("13") #=> nil
  #     @asari.search("fritters") #=> ["28"]
  #     @asari.remove_item("13") #=> nil
  #
  # Returns: nil if the request is successful (note that asking the index to
  #   delete an item that's not present in the index is still a successful
  #   request).
  # Raises: DocumentUpdateException if there's an issue communicating the
  #   request to the server.
  def remove_item(id)
    return nil if self.class.mode == :sandbox

    query = { "type" => "delete", "id" => id.to_s }
    doc_request query
  end

  # Internal: helper method: common logic for queries against the doc endpoint.
  #
  def doc_request(query)
    endpoint = "http://doc-#{search_domain}.#{aws_region}.cloudsearch.amazonaws.com/#{api_version}/documents/batch"

    options = { :body => [query].to_json, :headers => { "Content-Type" => "application/json"} }

    begin
      response = HTTParty.post(endpoint, options)
    rescue Exception => e
      ae = Asari::DocumentUpdateException.new("#{e.class}: #{e.message}")
      ae.set_backtrace e.backtrace
      raise ae
    end

    unless response.response.code == "200"
      raise Asari::DocumentUpdateException.new("#{response.response.code}: #{response.response.msg}")
    end

    nil
  end

  protected

  # Private: Builds the query from a passed hash
  #
  #     terms - a hash of the search query. %w(and or not) are reserved hash keys
  #             that build the logic of the query
  def boolean_query(terms = {}, options = {})
    reduce = lambda { |hash|
      hash.reduce("") do |memo, (key, value)|
        if %w(and or not).include?(key.to_s) && value.is_a?(Hash)
          sub_query = reduce.call(value)
          memo += "(#{key}%20#{sub_query})" unless sub_query.empty?
        else
          case value
            when Integer
              memo += "#{key}:#{ CGI.escape value }"
            when Range
              memo += CGI.escape("(range field=#{key} [#{value.min}, #{value.max}])")
            when Array
              condition = "(or%20"
              condition << value.map do |v|
                if v.is_a?(String)
                  "#{ key }:'#{ CGI.escape(v.to_s) }'"
                else
                  "#{ key }:#{ CGI.escape(v.to_s) }"
                end
              end.join("%20")
              condition << ")"
              memo += condition
            else
              memo += "#{key}:'#{ CGI.escape value.to_s }'" unless value.to_s.empty?
          end
        end
        memo
      end
    }
    reduce.call(terms)
  end

  def convert_date_or_time(obj)
    return obj unless [Time, Date, DateTime].include?(obj.class)
    obj.to_time.to_i
  end

  def normalize_sort(sort_param)
    sort_param << :asc if sort_param.size < 2
    sort_field, sort_direction = *sort_param
    "&sort=#{ sort_field } #{ sort_direction }"
  end


  def build_facets(facet_options)
    case facet_options
      when Array then build_facets_from_array(facet_options)
      when Hash then build_facets_from_hash(facet_options)
    end
  end

  def build_facets_from_array(facets)
    facets.inject("") do |facet_str, facet|
      case facet
        when String, Symbol
          facet_str << "&facet.#{ facet }=#{ CGI.escape("{}")}"
      end
    end
  end

  def build_facets_from_hash(facets)
    facets.inject("") do |facet_str, facet_options|
      facet_name = facet_options[0]
      facet_value = facet_options[1]
      facet_str << "&facet.#{ facet_name }=" << CGI.escape(build_facet_credentials(facet_value))
    end
  end

  def build_facet_credentials(facet_options)
    "{".tap do |facet_str|
      facet_str << facet_options.map do |option_name, option_value|
        case option_value
          when String then "#{ option_name}:'#{ option_value }'"
          when Numeric then "#{ option_name}:#{ option_value }"
        end
      end.join(",")
      facet_str << "}"
    end
  end

end

Asari.mode = :sandbox # default to sandbox
