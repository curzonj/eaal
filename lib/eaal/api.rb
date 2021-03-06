# EAAL::API class
# Usage Example:
#  api = EAAL::API.new("my keyID", "my API key")
#  result = api.Characters
#  result.characters.each{|character|
#      puts character.name
#  }
class EAAL::API
  attr_accessor :keyid, :vcode, :scope

  # constructor
  # Expects:
  # * keyID (String | Integer) the keyID
  # * vCode (String) the vCode
  # * scope (String) defaults to account
  def initialize(keyid, vcode, scope="account")
    self.keyid = keyid.to_s
    self.vcode = vcode.to_s
    self.scope = scope.to_s
  end

  # create an xml request according to the method called
  # this is used to dynamicaly create api calls and
  # should usually not be called directly
  # * method (const)
  # * args
  def method_missing(method, *args)
    scope = self.scope
    args_hash = args.first
    cache_only = (args_hash && args_hash.delete(:cache_only)) || false
    args_hash = {} unless args_hash
    self.request_xml(scope, method.id2name, args_hash, cache_only)
  end

  # make a request to the api. will use cache if set.
  # usually not called by the user directly
  # * scope (String)
  # * name (String)
  # * opts (Hash)
  def request_xml(scope, name, opts, cache_only = false)
    opts = EAAL.additional_request_parameters.merge(opts)
    xml = EAAL.cache.load(self.keyid, self.vcode, scope, name,opts)
    if (not xml) && (not cache_only)
      source = URI.parse(EAAL.api_base + scope + '/' + name +'.xml.aspx')
      req_path = source.path + format_url_request(opts.merge({
        :keyid => self.keyid,
        :vcode => self.vcode}))
      req = Net::HTTP::Get.new(req_path)
      req[EAAL.version_string]
      http = open_connection(source)
      res = http.request(req) #one request for now
      case res
      when Net::HTTPOK
      when Net::HTTPNotFound
        raise EAAL::Exception::APINotFoundError.new("The requested API (#{scope} / #{name}) could not be found.")
      else
        raise EAAL::Exception::HTTPError.new("An HTTP Error occured, body: " + res.body)
      end
      EAAL.cache.save(self.keyid, self.vcode, scope,name,opts, res.body)
      xml = res.body
    end
    if xml
      doc = Hpricot.XML(xml)
      result = EAAL::Result.new(scope.capitalize + name, doc)
    else 
      result = nil
    end
  end

  def open_connection(uri)
    http = Net::HTTP.new(uri.host, uri.port)
    if uri.scheme == 'https'
      http.use_ssl = true
      certs = EAAL.ssl_certs
      if certs && File.exists?(certs)
        if File.file?(certs)
          http.ca_file = certs
        else
          http.ca_path = certs
        end

        http.verify_mode = OpenSSL::SSL::VERIFY_PEER
        http.verify_depth = 5
      else
        logger.warn("No valid certificates found, will not verify vault cert")
        http.verify_mode = OpenSSL::SSL::VERIFY_NONE
      end
    end

    http
  end

  def logger
    EAAL.logger
  end

  # Turns a hash into ?var=baz&bam=boo
  # stolen from Reve (thx lisa)
  # * opts (Hash)
  def format_url_request(opts)
    req = ''

    opts.delete_if {|k,v| v.nil? }
    return req if opts.empty?

    opts.stringify_keys!
    opts = opts.keys.sort.map do |key|
      "#{CGI.escape(key.to_s)}=#{CGI.escape(opts[key].to_s)}"
    end
    req = '?' + opts.join('&')
  end

end
