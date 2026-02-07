# mastodon_client.rb
require 'faraday'
require 'json'
require 'net/http'
require 'uri'

class MastodonClient
  MAX_TOOT_LENGTH = 500  # 500자 제한

  def initialize(base_url, token)
    @base_url = base_url
    @token = token

    @conn = Faraday.new(url: @base_url) do |f|
      f.request :url_encoded
      f.response :raise_error
      f.adapter Faraday.default_adapter
    end
  end

  def verify_credentials
    result = get("/api/v1/accounts/verify_credentials")
    result["acct"] || result["username"]
  end

  def get(path, params = {})
    res = @conn.get(path) do |req|
      req.headers['Authorization'] = "Bearer #{@token}"
      req.headers['Content-Type'] = 'application/json'
      req.params.update(params) if params && !params.empty?
    end
    JSON.parse(res.body)
  end

  def post(path, body = {})
    res = @conn.post(path) do |req|
      req.headers['Authorization'] = "Bearer #{@token}"
      req.headers['Content-Type'] = 'application/json'
      req.body = body.to_json
    end
    JSON.parse(res.body)
  end

  def reply(status_hash, message)
    in_reply_to_id = status_hash["id"] || status_hash[:id]
    post("/api/v1/statuses", {
      status: message,
      in_reply_to_id: in_reply_to_id,
      visibility: "unlisted"
    })
  rescue => e
    puts "[MastodonClient] reply 실패: #{e.message}"
    nil
  end

  # 여러 사용자 멘션하면서 답장
  def reply_with_mentions(status_hash, message, user_ids)
    reply_with_mentions_visibility(status_hash, message, user_ids, "unlisted")
  end

  # 여러 사용자 멘션하면서 답장 (visibility 지정 가능)
  def reply_with_mentions_visibility(status_hash, message, user_ids, visibility = "unlisted")
    in_reply_to_id = status_hash["id"] || status_hash[:id]

    mentions = user_ids.map { |id| "@#{id}" }.join(' ')
    full_message = "#{mentions}\n#{message}"

    # 500자 넘으면 스레드로 분할
    if full_message.length > MAX_TOOT_LENGTH
      reply_with_mentions_thread_visibility(status_hash, message, user_ids, visibility)
    else
      post("/api/v1/statuses", {
        status: full_message,
        in_reply_to_id: in_reply_to_id,
        visibility: visibility
      })
    end
  rescue => e
    puts "[MastodonClient] reply_with_mentions_visibility 실패: #{e.message}"
    nil
  end

  # 긴 메시지를 스레드로 분할해서 발송
  def reply_with_mentions_thread(status_hash, message, user_ids)
    reply_with_mentions_thread_visibility(status_hash, message, user_ids, "unlisted")
  end

  # 긴 메시지를 스레드로 분할해서 발송 (visibility 지정 가능)
  def reply_with_mentions_thread_visibility(status_hash, message, user_ids, visibility = "unlisted")
    in_reply_to_id = status_hash["id"] || status_hash[:id]
    mentions = user_ids.map { |id| "@#{id}" }.join(' ')
    mentions_length = mentions.length + 1  # +1 for newline

    # 메시지를 500자 이하 청크로 분할
    chunks = split_message(message, MAX_TOOT_LENGTH - mentions_length)

    last_status = nil
    chunks.each_with_index do |chunk, index|
      full_message = "#{mentions}\n#{chunk}"

      begin
        result = post("/api/v1/statuses", {
          status: full_message,
          in_reply_to_id: in_reply_to_id,
          visibility: visibility
        })

        # 다음 메시지는 이전 메시지에 답장
        in_reply_to_id = result["id"] if result
        last_status = result

        # API 제한 방지를 위해 0.5초 대기
        sleep 0.5 if index < chunks.length - 1

      rescue => e
        puts "[MastodonClient] 스레드 #{index + 1}/#{chunks.length} 발송 실패: #{e.message}"
      end
    end

    last_status
  end

  def stream(limit: 20, interval: 2, dismiss: false)
    since_id = nil
    @processed_notifications ||= {}  # 처리된 알림 ID 캐싱

    # 봇 시작 시 현재 최신 알림 ID를 since_id로 설정 (이전 알림 무시)
    begin
      initial_notifications = get("/api/v1/notifications", { limit: 1 })
      if initial_notifications.any?
        since_id = initial_notifications.first["id"]
        puts "[MastodonClient] 봇 시작 - 최신 알림 ID: #{since_id}"
        puts "[MastodonClient] 이전 알림은 무시하고 새 알림만 처리합니다."
      end
    rescue => e
      puts "[MastodonClient] 초기 알림 ID 가져오기 실패: #{e.message}"
    end

    loop do
      begin
        notifications = get("/api/v1/notifications", { limit: limit, since_id: since_id })
        notifications = notifications.reverse

        notifications.each do |n|
          notification_id = n["id"]

          # 이미 처리된 알림인지 확인 (중복 방지)
          if @processed_notifications[notification_id]
            puts "[MastodonClient] 중복 알림 무시: #{notification_id}"
            next
          end

          since_id = notification_id if since_id.nil? || notification_id.to_i > since_id.to_i

          # 처리된 알림 ID 캐싱 (최대 1000개 유지)
          @processed_notifications[notification_id] = Time.now
          cleanup_processed_notifications if @processed_notifications.size > 1000

          yield n

          if dismiss
            begin
              post("/api/v1/notifications/#{notification_id}/dismiss", {})
            rescue => e
              puts "[MastodonClient] dismiss 실패: #{e.message}"
            end
          end
        end
      rescue => e
        puts "[MastodonClient] 스트림 처리 오류: #{e.message}"
      end

      sleep interval
    end
  end

  # 오래된 처리된 알림 ID 정리
  def cleanup_processed_notifications
    return unless @processed_notifications

    # 30분 이상 지난 알림 ID 삭제
    cutoff_time = Time.now - 1800
    @processed_notifications.delete_if { |_id, time| time < cutoff_time }
  end

  # SSE 스트리밍으로 user 스트림 구독
  def stream_user(&block)
    uri = URI.parse("#{@base_url}/api/v1/streaming/user")

    Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http|
      request = Net::HTTP::Get.new(uri)
      request['Authorization'] = "Bearer #{@token}"
      request['Accept'] = 'text/event-stream'

      http.request(request) do |response|
        buffer = ""
        event_type = nil

        response.read_body do |chunk|
          buffer += chunk

          while buffer.include?("\n\n")
            event_data, buffer = buffer.split("\n\n", 2)

            event_data.each_line do |line|
              line = line.strip
              if line.start_with?("event:")
                event_type = line.sub("event:", "").strip
              elsif line.start_with?("data:")
                data = line.sub("data:", "").strip

                if event_type == "notification" && !data.empty?
                  begin
                    notification = JSON.parse(data)
                    if notification["type"] == "mention" && notification["status"]
                      status = notification["status"]
                      yield symbolize_keys(status)
                    end
                  rescue JSON::ParserError => e
                    puts "[MastodonClient] JSON 파싱 오류: #{e.message}"
                  end
                end
              end
            end
          end
        end
      end
    end
  end

  private

  def symbolize_keys(hash)
    return hash unless hash.is_a?(Hash)
    hash.each_with_object({}) do |(key, value), result|
      new_key = key.is_a?(String) ? key.to_sym : key
      new_value = value.is_a?(Hash) ? symbolize_keys(value) : value
      result[new_key] = new_value
    end
  end

  # 메시지를 자연스럽게 분할 (줄바꿈 기준)
  def split_message(message, max_length)
    return [message] if message.length <= max_length
    
    chunks = []
    current_chunk = ""
    
    lines = message.split("\n")
    
    lines.each do |line|
      # 한 줄이 max_length보다 길면 강제 분할
      if line.length > max_length
        # 현재 청크가 있으면 저장
        chunks << current_chunk.strip if current_chunk.length > 0
        
        # 긴 줄을 강제 분할
        while line.length > 0
          chunks << line[0...max_length]
          line = line[max_length..-1] || ""
        end
        
        current_chunk = ""
      else
        # 현재 청크에 추가했을 때 max_length를 넘으면
        if (current_chunk + "\n" + line).length > max_length
          chunks << current_chunk.strip if current_chunk.length > 0
          current_chunk = line
        else
          current_chunk += (current_chunk.empty? ? "" : "\n") + line
        end
      end
    end
    
    # 마지막 청크 추가
    chunks << current_chunk.strip if current_chunk.length > 0
    
    chunks
  end
end
