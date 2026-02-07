# mastodon_client.rb
require 'faraday'
require 'json'

class MastodonClient
  def initialize(base_url, token)
    @base_url = base_url
    @token = token

    @conn = Faraday.new(url: @base_url) do |f|
      f.request :url_encoded
      f.response :raise_error
      f.response :follow_redirects
      f.adapter Faraday.default_adapter
    end
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
    in_reply_to_id = status_hash["id"] || status_hash[:id]
    
    # 멘션 추가
    mentions = user_ids.map { |id| "@#{id}" }.join(' ')
    full_message = "#{mentions}\n#{message}"
    
    post("/api/v1/statuses", {
      status: full_message,
      in_reply_to_id: in_reply_to_id,
      visibility: "unlisted"
    })
  rescue => e
    puts "[MastodonClient] reply_with_mentions 실패: #{e.message}"
    nil
  end

  def stream(limit: 20, interval: 2, dismiss: false)
    since_id = nil
    
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
      notifications = get("/api/v1/notifications", { limit: limit, since_id: since_id })
      notifications = notifications.reverse

      notifications.each do |n|
        since_id = n["id"] if since_id.nil? || n["id"].to_i > since_id.to_i

        yield n

        if dismiss
          begin
            post("/api/v1/notifications/#{n['id']}/dismiss", {})
          rescue => e
            puts "[MastodonClient] dismiss 실패: #{e.message}"
          end
        end
      end

      sleep interval
    end
  end
end
