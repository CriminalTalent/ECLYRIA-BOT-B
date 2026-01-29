require 'mastodon'
require 'net/http'
require 'json'

class MastodonClient
  def initialize(base_url:, token:)
    @base_url = base_url
    @token = token
    @client = Mastodon::REST::Client.new(base_url: base_url, bearer_token: token)
  end

  def reply(status, message)
    @client.create_status(message, in_reply_to_id: status[:id], visibility: 'public')
  rescue => e
    puts "[마스토돈 오류] reply 실패: #{e.message}"
  end

  def reply_with_mentions(status, message, user_ids)
    mentions = user_ids.map { |id| "@#{id}" }.join(' ')
    full_message = "#{mentions}\n#{message}"
    @client.create_status(full_message, in_reply_to_id: status[:id], visibility: 'public')
  rescue => e
    puts "[마스토돈 오류] reply_with_mentions 실패: #{e.message}"
  end

  def send_dm(user_id, message)
    @client.create_status("@#{user_id} #{message}", visibility: 'direct')
  rescue => e
    puts "[마스토돈 오류] send_dm 실패: #{e.message}"
  end

  def stream_user(&block)
    uri = URI("#{@base_url}/api/v1/streaming/user")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.read_timeout = 600

    request = Net::HTTP::Get.new(uri)
    request['Authorization'] = "Bearer #{@token}"

    http.request(request) do |response|
      buffer = ''
      response.read_body do |chunk|
        buffer += chunk
        while buffer.include?("\n\n")
          event_text, buffer = buffer.split("\n\n", 2)
          process_stream_event(event_text, &block)
        end
      end
    end
  end

  private

  def process_stream_event(event_text, &block)
    lines = event_text.split("\n")
    event_type = nil
    data = nil

    lines.each do |line|
      if line.start_with?('event: ')
        event_type = line.sub('event: ', '').strip
      elsif line.start_with?('data: ')
        data = line.sub('data: ', '').strip
      end
    end

    return unless event_type == 'notification' && data

    notification = JSON.parse(data, symbolize_names: true)
    return unless notification[:type] == 'mention'

    yield notification[:status] if block_given?
  rescue JSON::ParserError => e
    puts "[스트리밍 오류] JSON 파싱 실패: #{e.message}"
  end
end
