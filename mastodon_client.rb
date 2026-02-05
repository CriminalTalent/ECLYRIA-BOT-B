# mastodon_client.rb
require 'net/http'
require 'json'
require 'uri'

class MastodonClient
  def initialize(base_url:, token:)
    @base_url = base_url.to_s.strip
    @token = token.to_s.strip
  end

  # -----------------------------
  # 계정 확인
  # -----------------------------
  def verify_credentials
    uri = URI("#{@base_url}/api/v1/accounts/verify_credentials")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == 'https')
    http.read_timeout = 30
    http.open_timeout = 10

    req = Net::HTTP::Get.new(uri)
    req['Authorization'] = "Bearer #{@token}"

    res = http.request(req)
    unless res.is_a?(Net::HTTPSuccess)
      raise "HTTP #{res.code}: #{res.body}"
    end

    data = JSON.parse(res.body, symbolize_names: true)
    data[:acct] || data[:username] || "unknown"
  end

  # -----------------------------
  # visibility 규칙:
  # - DM(direct)로 오면 답도 direct
  # - public/unlisted/private로 오면 그대로 따라감
  # - 다인전투/전투결과는 항상 참가자 멘션 붙여서 보냄
  # -----------------------------
  def infer_visibility_from_status(status)
    v = status.is_a?(Hash) ? status[:visibility] : nil
    v = v.to_s.strip
    v.empty? ? 'public' : v
  end

  def reply(status, message, visibility: nil)
    return unless status.is_a?(Hash)

    sender = status.dig(:account, :acct) || "unknown"
    vis = (visibility || infer_visibility_from_status(status))

    full_message = "@#{sender}\n#{message}"
    post_status(full_message, in_reply_to_id: status[:id], visibility: vis)
  rescue => e
    puts "[마스토돈 오류] reply 실패: #{e.message}"
  end

  def reply_with_mentions(status, message, user_ids, visibility: nil)
    return unless status.is_a?(Hash)

    vis = (visibility || infer_visibility_from_status(status))
    ids = Array(user_ids).map { |u| u.to_s.strip }.reject(&:empty?).uniq

    mentions = ids.map { |id| "@#{id}" }.join(' ')
    full_message = "#{mentions}\n#{message}"

    post_status(full_message, in_reply_to_id: status[:id], visibility: vis)
  rescue => e
    puts "[마스토돈 오류] reply_with_mentions 실패: #{e.message}"
  end

  def send_dm(user_id, message)
    post_status("@#{user_id} #{message}", visibility: 'direct')
  rescue => e
    puts "[마스토돈 오류] send_dm 실패: #{e.message}"
  end

  # -----------------------------
  # 유저 스트림(멘션 알림 수신)
  # -----------------------------
  def stream_user(&block)
    uri = URI("#{@base_url}/api/v1/streaming/user")

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == 'https')
    http.read_timeout = 600
    http.open_timeout = 30

    request = Net::HTTP::Get.new(uri)
    request['Authorization'] = "Bearer #{@token}"

    http.request(request) do |response|
      buffer = ''
      response.read_body do |chunk|
        buffer << chunk
        while buffer.include?("\n\n")
          event_text, buffer = buffer.split("\n\n", 2)
          process_stream_event(event_text, &block)
        end
      end
    end
  end

  private

  def post_status(text, options = {})
    uri = URI("#{@base_url}/api/v1/statuses")

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == 'https')
    http.read_timeout = 30
    http.open_timeout = 10

    request = Net::HTTP::Post.new(uri)
    request['Authorization'] = "Bearer #{@token}"
    request['Content-Type'] = 'application/json'

    body = { status: text }.merge(options)
    request.body = body.to_json

    response = http.request(request)
    unless response.is_a?(Net::HTTPSuccess)
      puts "[마스토돈 API 오류] #{response.code}: #{response.body}"
    end
    response
  end

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
    return unless notification.is_a?(Hash)
    return unless notification[:type] == 'mention'

    st = notification[:status]
    return unless st.is_a?(Hash) # ✅ 여기서 Hash 아닌 건 스킵

    yield st if block_given?
  rescue JSON::ParserError => e
    puts "[스트리밍 오류] JSON 파싱 실패: #{e.message}"
  rescue => e
    puts "[스트리밍 오류] 이벤트 처리 실패: #{e.message}"
  end
end
