# mastodon_client.rb
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
      bearer_token: @token,
      timeout: { connect: 2, read: 5, write: 20 }
    )
    @streamer = Mastodon::Streaming::Client.new(
      base_url: @base_url,
      bearer_token: @token,
      timeout: { connect: 2, read: 30, write: 20 }
    )

    # 봇 계정 username 설정 (환경변수 또는 기본값)
    @bot_username = (ENV['BOT_USERNAME'] || 'battle').downcase
    @bot_acct = @bot_username
    puts "[봇 계정] @#{@bot_username}"
  end

  # ==========================================
  #  🔥 폴링 방식으로 알림 가져오기 (백업용)
  # ==========================================
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

  # ==========================================
  #  🔥 안정형 stream_user (DM + 멘션 모두 처리)
  # ==========================================
  def stream_user(&block)
    puts "[마스토돈] user 스트림 구독 시작..."

    @streamer.user do |event|
      begin
        # event가 Mastodon::Status 객체인 경우
        if event.is_a?(Mastodon::Status)
          # 해시로 변환 (깊은 변환)
          status = deep_symbolize(event.to_h)

          # 발신자 정보 확인
          next unless status[:account] && status[:account][:acct]

          # DM 처리 - 자신에게 온 DM만
          if status[:visibility] == "direct"
            # content에서 자신의 username이 있는지 확인
            content_lower = status[:content].to_s.downcase
            if content_lower.include?("@#{@bot_username}") || content_lower.include?("@#{@bot_acct}")
              block.call(status)
            end
            next
          end

          # 멘션 처리 - content에 자신의 username이 있는지 확인
          if status[:mentions] && status[:mentions].any?
            content_lower = status[:content].to_s.downcase
            if content_lower.include?("@#{@bot_username}") || content_lower.include?("@#{@bot_acct}")
              block.call(status)
            end
            next
          end
        end

        # event가 Mastodon::Notification 객체인 경우
        if event.is_a?(Mastodon::Notification)
          next unless event.type == "mention"
          next unless event.status

          status = deep_symbolize(event.status.to_h)
          next unless status[:account] && status[:account][:acct]

          # content에서 자신의 username이 있는지 확인
          content_lower = status[:content].to_s.downcase
          if content_lower.include?("@#{@bot_username}") || content_lower.include?("@#{@bot_acct}")
            block.call(status)
          end
          next
        end

      rescue => e
        puts "[스트리밍 처리 오류] #{e.class}: #{e.message}"
        puts e.backtrace.first(3)
      end
    end
  end

  # ==========================================
  #  기본 reply (DM은 DM으로, 멘션은 public으로)
  # ==========================================
  def reply(to_status, text)
    begin
      status_id = to_status.is_a?(Hash) ? to_status[:id] : to_status.id
      visibility = to_status.is_a?(Hash) ? to_status[:visibility] : to_status.visibility

      return unless status_id

      # 문자열로 변환
      status_id = status_id.to_s

      result = @client.create_status(
        text,
        in_reply_to_id: status_id,
        visibility: visibility == "direct" ? "direct" : "public"
      )
      
      # 생성된 status ID 반환 (해시 형태로)
      return { id: result.id.to_s } if result
    rescue => e
      puts "[에러] reply 실패: #{e.message}"
      puts e.backtrace.first(3)
      nil
    end
  end

  # ==========================================
  #  전투용 멘션 답글 (참여자 태그)
  # ==========================================
  def reply_with_mentions(to_status, text, participant_ids)
    begin
      status_id = to_status.is_a?(Hash) ? to_status[:id] : to_status.id

      return nil unless status_id

      # 문자열로 변환
      status_id = status_id.to_s

      mentions = participant_ids.map { |id| "@#{id}" }.join(' ')
      full_text = "#{mentions}\n#{text}"

      result = @client.create_status(
        full_text,
        in_reply_to_id: status_id,
        visibility: "public"
      )
      
      # 생성된 status ID 반환 (해시 형태로)
      return { id: result.id.to_s } if result
    rescue => e
      puts "[에러] 멘션 답글 실패: #{e.message}"
      puts e.backtrace.first(3)
      nil
    end
  end

  # ==========================================
  #  공개 포스트
  # ==========================================
  def post(text, visibility: 'public')
    begin
      @client.create_status(text, visibility: visibility)
    rescue => e
      puts "[에러] post 실패: #{e.message}"
    end
  end

  # ==========================================
  #  DM 전송
  # ==========================================
  def dm(user_id, text)
    begin
      @client.create_status("@#{user_id} #{text}", visibility: 'direct')
    rescue => e
      puts "[에러] DM 전송 실패: #{e.message}"
    end
  end

  # ==========================================
  #  계정 검색
  # ==========================================
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

  # 깊은 심볼 변환 (중첩된 해시/배열 모두 변환)
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
