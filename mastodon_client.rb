# mastodon_client.rb
require 'mastodon'
require 'json'

class MastodonClient
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
          status = event.to_h.transform_keys(&:to_sym)
          
          # DM 처리
          if status[:visibility] == "direct"
            block.call(status)
            next
          end
          
          # 멘션 처리
          if status[:mentions] && status[:mentions].any?
            block.call(status)
            next
          end
        end
        
        # event가 Mastodon::Notification 객체인 경우
        if event.is_a?(Mastodon::Notification)
          next unless event.type == "mention"
          next unless event.status
          
          status = event.status.to_h.transform_keys(&:to_sym)
          block.call(status)
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
      
      @client.create_status(
        text,
        in_reply_to_id: status_id,
        visibility: visibility == "direct" ? "direct" : "public"
      )
    rescue => e
      puts "[에러] reply 실패: #{e.message}"
    end
  end

  # ==========================================
  #  전투용 멘션 답글 (참여자 태그)
  # ==========================================
  def reply_with_mentions(to_status, text, participant_ids)
    begin
      status_id = to_status.is_a?(Hash) ? to_status[:id] : to_status.id
      
      mentions = participant_ids.map { |id| "@#{id}" }.join(' ')
      full_text = "#{mentions}\n#{text}"
      
      @client.create_status(
        full_text,
        in_reply_to_id: status_id,
        visibility: "public"
      )
    rescue => e
      puts "[에러] 멘션 답글 실패: #{e.message}"
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
end
