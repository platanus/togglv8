class TogglBaseApi

  attr_reader :conn

  def self.toggl_api_url
    'https://www.toggl.com'
  end

  def self.api_token
    'api_token'
  end

  def self.max_retries
    3
  end

  def self.delay_sec
    1
  end

  def self.toggl_file
     '.toggl'
  end

  def initialize(username=nil, password=self.class.api_token, opts={})
    @logger = Logger.new(STDOUT)
    @logger.level = Logger::WARN

    if username.nil? && password == self.class.api_token
      toggl_api_file = File.join(Dir.home, self.class.toggl_file)
      if FileTest.exist?(toggl_api_file) then
        username = IO.read(toggl_api_file)
      else
        raise "Expecting\n" +
          " 1) api_token in file #{toggl_api_file}, or\n" +
          " 2) parameter: (api_token), or\n" +
          " 3) parameters: (username, password).\n" +
          "\n\tSee https://github.com/toggl/toggl_api_docs/blob/master/chapters/authentication.md"
      end
    end

    @conn = self.class.connection(username, password, opts)
  end

  def debug(debug=true)
    if debug
      @logger.level = Logger::DEBUG
    else
      @logger.level = Logger::WARN
    end
  end

#---------#
# Private #
#---------#

private

  attr_writer :conn

  def self.connection(username, password, opts={})
    Faraday.new(:url => toggl_api_url, :ssl => {:verify => true}) do |faraday|
      faraday.request :url_encoded
      faraday.response :logger, Logger.new('faraday.log') if opts[:log]
      faraday.adapter Faraday.default_adapter
      faraday.headers = { "Content-Type" => "application/json" }
      faraday.basic_auth username, password
    end
  end

  def requireParams(params, fields=[])
    raise ArgumentError, 'params is not a Hash' unless params.is_a? Hash
    return if fields.empty?
    errors = []
    for f in fields
      errors.push("params[#{f}] is required") unless params.has_key?(f)
    end
    raise ArgumentError, errors.join(', ') if !errors.empty?
  end

  def _call_api(procs)
    @logger.debug(procs[:debug_output].call)
    full_resp = nil
    i = 0
    loop do
      i += 1
      full_resp = procs[:api_call].call
      @logger.ap(full_resp.env, :debug)
      break if full_resp.status != 429 || i >= self.class.max_retries
      sleep(self.class.delay_sec)
    end

    raise "HTTP Status: #{full_resp.status}" unless full_resp.success?
    return {} if full_resp.body.nil? || full_resp.body == 'null'

    full_resp
  end

  def get(resource)
    resource.gsub!('+', '%2B')
    full_resp = _call_api(debug_output: lambda { "GET #{resource}" },
                          api_call: lambda { self.conn.get(resource) } )
    return {} if full_resp == {}
    resp = Oj.load(full_resp.body)
    return resp['data'] if resp.respond_to?(:has_key?) && resp.has_key?('data')
    resp
  end

  def post(resource, data='')
    resource.gsub!('+', '%2B')
    full_resp = _call_api(debug_output: lambda { "POST #{resource} / #{data}" },
                          api_call: lambda { self.conn.post(resource, Oj.dump(data)) } )
    return {} if full_resp == {}
    resp = Oj.load(full_resp.body)
    resp['data']
  end

  def put(resource, data='')
    resource.gsub!('+', '%2B')
    full_resp = _call_api(debug_output: lambda { "PUT #{resource} / #{data}" },
                          api_call: lambda { self.conn.put(resource, Oj.dump(data)) } )
    return {} if full_resp == {}
    resp = Oj.load(full_resp.body)
    resp['data']
  end

  def delete(resource)
    resource.gsub!('+', '%2B')
    full_resp = _call_api(debug_output: lambda { "DELETE #{resource}" },
                          api_call: lambda { self.conn.delete(resource) } )
    return {} if full_resp == {}
    full_resp.body
  end
end
