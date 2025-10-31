require 'net/http'
require 'json'
require 'uri'

class MastodonClient
  def initialize(base_url, access_token)
    @base_url = base_url
    @access_token = access_token
  end

  def notifications(since_id: nil, limit: 40)
    uri = URI("#{@base_url}/api/v1/notifications")
    params = { limit: limit }
    params[:since_id] = since_id if since_id
    uri.query = URI.encode_www_form(params)

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == 'https')

    request = Net::HTTP::Get.new(uri.request_uri)
    request['Authorization'] = "Bearer #{@access_token}"

    response = http.request(request)
    JSON.parse(response.body)
  rescue => e
    puts "Error fetching notifications: #{e.message}"
    []
  end

  def reply(status_id, message, visibility: 'public')
    uri = URI("#{@base_url}/api/v1/statuses")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == 'https')

    request = Net::HTTP::Post.new(uri.path)
    request['Authorization'] = "Bearer #{@access_token}"
    request['Content-Type'] = 'application/json'

    body = {
      status: message,
      in_reply_to_id: status_id,
      visibility: visibility
    }
    request.body = body.to_json

    response = http.request(request)
    JSON.parse(response.body)
  rescue => e
    puts "Error replying: #{e.message}"
    nil
  end

  def post(message, visibility: 'public')
    uri = URI("#{@base_url}/api/v1/statuses")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == 'https')

    request = Net::HTTP::Post.new(uri.path)
    request['Authorization'] = "Bearer #{@access_token}"
    request['Content-Type'] = 'application/json'

    body = {
      status: message,
      visibility: visibility
    }
    request.body = body.to_json

    response = http.request(request)
    JSON.parse(response.body)
  rescue => e
    puts "Error posting: #{e.message}"
    nil
  end

  def dm(user_id, message)
    uri = URI("#{@base_url}/api/v1/statuses")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == 'https')

    request = Net::HTTP::Post.new(uri.path)
    request['Authorization'] = "Bearer #{@access_token}"
    request['Content-Type'] = 'application/json'

    body = {
      status: "#{user_id} #{message}",
      visibility: 'direct'
    }
    request.body = body.to_json

    response = http.request(request)
    JSON.parse(response.body)
  rescue => e
    puts "Error sending DM: #{e.message}"
    nil
  end

  def account_search(query)
    uri = URI("#{@base_url}/api/v1/accounts/search")
    params = { q: query, limit: 5 }
    uri.query = URI.encode_www_form(params)

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == 'https')

    request = Net::HTTP::Get.new(uri.request_uri)
    request['Authorization'] = "Bearer #{@access_token}"

    response = http.request(request)
    JSON.parse(response.body)
  rescue => e
    puts "Error searching accounts: #{e.message}"
    []
  end
end
