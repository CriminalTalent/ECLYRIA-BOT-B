# mastodon_client.rb
require 'mastodon'
require 'uri'
require 'json'

class MastodonClient
  def initialize(base_url:, token:)
    @base_url = base_url
    @client = Mastodon::REST::Client.new(
      base_url: base_url,
      bearer_token: token
    )
    
    # Streaming 클라이언트 초기화를 지연시킴
    @streamer = nil
  end

  # 스트리밍 클라이언트 초기화 (필요할 때만)
  def get_streamer
    @streamer ||= Mastodon::Streaming::Client.new(
      base_url: @base_url,
      bearer_token: @client.instance_variable_get(:@bearer_token)
    )
  rescue => e
    puts "[경고] 스트리밍 클라이언트 초기화 실패: #{e.message}"
    nil
  end

  # 실시간 멘션 스트리밍 처리
  def stream_user(&block)
    puts "[마스토돈] 멘션 스트리밍 시작..."
    streamer = get_streamer
    return unless streamer
    
    streamer.user do |event|
      if event.is_a?(Mastodon::Notification) && event.type == 'mention'
        block.call(event)
      end
    end
  rescue => e
    puts "[에러] 스트리밍 중단됨: #{e.message}"
    sleep 5
    retry
  end

  # 멘션에 답글 작성 (frozen string 문제 해결)
  def reply(to_acct, message, in_reply_to_id: nil)
    begin
      puts "[마스토돈] → @#{to_acct} 에게 응답 전송"
      status_text = "@#{to_acct} #{message}".dup
      @client.create_status(
        status_text,
        visibility: 'unlisted',
        in_reply_to_id: in_reply_to_id
      )
    rescue => e
      puts "[에러] 응답 전송 실패: #{e.message}"
    end
  end

  # 전체 공지용 푸시
  def broadcast(message)
    begin
      puts "[마스토돈] → 전체 공지 전송"
      @client.create_status(
        message,
        visibility: 'public'
      )
    rescue => e
      puts "[에러] 공지 전송 실패: #{e.message}"
    end
  end

  # 일반 포스트 (전투봇용)
  def say(message)
    begin
      puts "[마스토돈] → 일반 포스트 전송"
      @client.create_status(
        message,
        visibility: 'public'
      )
    rescue => e
      puts "[에러] 포스트 전송 실패: #{e.message}"
    end
  end

  # DM 전송
  def dm(to_acct, message)
    begin
      puts "[마스토돈] → @#{to_acct} DM 전송"
      status_text = "@#{to_acct} #{message}".dup
      @client.create_status(
        status_text,
        visibility: 'direct'
      )
    rescue => e
      puts "[에러] DM 전송 실패: #{e.message}"
    end
  end

  def me
    @client.verify_credentials.acct
  end
end
