require 'mastodon'
require 'json'
require 'net/http'
require 'uri'

class MastodonClient
  attr_reader :bot_username

  def initialize(base_url:, token:)
    @base_url = base_url
    @token = token
    @client = Mastodon::REST::Client.new(
      base_url: @base_url,
      bearer_token: @token
    )
    @streamer = Mastodon::Streaming::Client.new(
      base_url: @base_url,
      bearer_token: @token
    )

    @bot_username = (ENV['BOT_USERNAME'] || 'battle').downcase
    @bot_acct = @bot_username
    puts "[봇 계정] @#{@bot_username}"
  end

  def notifications(limit: 40)
    uri = URI("#{@base_url}/api/v1/notifications?limit=#{limit}")
    request = Net::HTTP::Get.new(uri)
    request['Authorization'] = "Bearer #{@token}"
    
    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
      http.request(request)
    end
    
    if response.code == '200'
      JSON.parse(response.body)
    else
      puts "[알림 가져오기 실패] #{response.code}: #{response.body}"
      []
    end
  rescue => e
    puts "[알림 가져오기 오류] #{e.class}: #{e.message}"
    []
  end

  def stream_user(&block)
    puts "[마스토돈] user 스트림 구독 시작... (@#{@bot_username} 멘션만 처리)"

    @streamer.user do |event|
      begin
        # Notification 이벤트만 처리 (중복 방지)
        if event.is_a?(Mastodon::Notification)
          next unless event.type == "mention"
          next unless event.status

          status = deep_symbolize(event.status.to_h)
          next unless status[:account] && status[:account][:acct]

          if status[:mentions] && status[:mentions].any?
            has_battle_mention = status[:mentions].any? do |mention|
              mention[:username].to_s.downcase == @bot_username.downcase ||
              mention[:acct].to_s.downcase == @bot_acct.downcase
            end
            
            if has_battle_mention
              block.call(status)
            end
          end
        end

      rescue => e
        puts "[스트리밍 처리 오류] #{e.class}: #{e.message}"
        puts e.backtrace.first(3)
      end
    end
  end

  def reply(to_status, text)
    begin
      status_id = to_status.is_a?(Hash) ? to_status[:id] : to_status.id
      visibility = to_status.is_a?(Hash) ? to_status[:visibility] : to_status.visibility

      unless status_id
        puts "[에러] reply: status_id가 없음"
        return nil
      end

      status_id = status_id.to_s

      result = @client.create_status(
        text,
        in_reply_to_id: status_id,
        visibility: visibility == "direct" ? "direct" : "public"
      )
      
      if result && result.respond_to?(:id) && result.id
        puts "[성공] reply ID: #{result.id}"
        return { id: result.id.to_s }
      else
        puts "[경고] reply: create_status가 빈 결과 반환, 독립 게시물로 재시도"
        result2 = @client.create_status(text, visibility: "public")
        return result2 && result2.id ? { id: result2.id.to_s } : nil
      end
      
    rescue => e
      puts "[에러] reply 실패: #{e.class}: #{e.message}"
      puts e.backtrace.first(3)
      
      begin
        puts "[재시도] 독립 게시물로 전송"
        result = @client.create_status(text, visibility: "public")
        return result && result.id ? { id: result.id.to_s } : nil
      rescue => retry_error
        puts "[에러] reply 재시도 실패: #{retry_error.message}"
        return nil
      end
    end
  end

  def reply_direct(to_status, text)
    begin
      status_id = to_status.is_a?(Hash) ? to_status[:id] : to_status.id

      unless status_id
        puts "[에러] reply_direct: status_id가 없음"
        return nil
      end

      status_id = status_id.to_s

      # HTTP 직접 요청으로 direct 답글
      uri = URI("#{@base_url}/api/v1/statuses")
      request = Net::HTTP::Post.new(uri)
      request['Authorization'] = "Bearer #{@token}"
      request['Content-Type'] = 'application/json'
      request.body = {
        status: text,
        in_reply_to_id: status_id,
        visibility: 'direct'
      }.to_json

      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
        http.request(request)
      end

      if response.code == '200'
        result = JSON.parse(response.body)
        puts "[성공] Direct 답글 ID: #{result['id']}"
        return { id: result['id'].to_s }
      else
        puts "[에러] HTTP #{response.code}: #{response.body[0..200]}"
        return nil
      end
      
    rescue => e
      puts "[에러] reply_direct 실패: #{e.class}: #{e.message}"
      puts e.backtrace.first(5)
      return nil
    end
  end

  def reply_with_mentions(to_status, text, participant_ids)
    begin
      status_id = to_status.is_a?(Hash) ? to_status[:id] : to_status.id

      unless status_id
        puts "[에러] reply_with_mentions: status_id가 없음"
        return nil
      end

      status_id = status_id.to_s
      mentions = participant_ids.map { |id| "@#{id}" }.join(' ')
      full_text = "#{mentions}\n#{text}"
      
      puts "[디버그] 답글 전송: status_id=#{status_id}, 길이=#{full_text.length}"

      # 직접 HTTP 요청 사용 (gem 우회)
      uri = URI("#{@base_url}/api/v1/statuses")
      request = Net::HTTP::Post.new(uri)
      request['Authorization'] = "Bearer #{@token}"
      request['Content-Type'] = 'application/json'
      request.body = {
        status: full_text,
        in_reply_to_id: status_id,
        visibility: 'public'
      }.to_json

      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
        http.request(request)
      end

      if response.code == '200'
        result = JSON.parse(response.body)
        puts "[성공] 답글 ID: #{result['id']}"
        return { id: result['id'].to_s }
      else
        puts "[에러] HTTP #{response.code}: #{response.body[0..200]}"
        return nil
      end
      
    rescue => e
      puts "[에러] reply_with_mentions 실패: #{e.class}: #{e.message}"
      puts e.backtrace.first(5)
      return nil
    end
  end

  def post(text, visibility: 'public')
    begin
      result = @client.create_status(text, visibility: visibility)
      if result && result.respond_to?(:id) && result.id
        return { id: result.id.to_s }
      else
        puts "[경고] post: 빈 결과 반환"
        return nil
      end
    rescue => e
      puts "[에러] post 실패: #{e.message}"
      return nil
    end
  end

  def dm(user_id, text)
    begin
      @client.create_status("@#{user_id} #{text}", visibility: 'direct')
    rescue => e
      puts "[에러] DM 전송 실패: #{e.message}"
    end
  end

  def account_search(query)
    begin
      results = @client.search(query, resolve: true)
      accounts = results.accounts || []
      accounts.map do |account|
        {
          'id' => account.id,
          'username' => account.username,
          'acct' => account.acct,
          'display_name' => account.display_name
        }
      end
    rescue => e
      puts "[에러] 계정 검색 실패: #{e.message}"
      []
    end
  end

  private

  def deep_symbolize(obj)
    case obj
    when Hash
      obj.each_with_object({}) do |(key, value), result|
        result[key.to_sym] = deep_symbolize(value)
      end
    when Array
      obj.map { |item| deep_symbolize(item) }
    else
      obj
    end
  end
end
