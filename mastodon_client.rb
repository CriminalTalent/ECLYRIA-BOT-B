# mastodon_client.rb
require 'mastodon'
require 'uri'
require 'json'
require 'dotenv'
Dotenv.load('.env')

class MastodonClient
  def initialize(base_url:, token:)
    @base_url = base_url
    @token = token
    @client = Mastodon::REST::Client.new(
      base_url: base_url,
      bearer_token: token
    )
    
    @streamer = nil
  end

  def get_streamer
    @streamer ||= Mastodon::Streaming::Client.new(
      base_url: @base_url,
      bearer_token: @token
    )
  rescue => e
    puts "[경고] 스트리밍 클라이언트 초기화 실패: #{e.message}"
    nil
  end

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

  # 통합 reply 메서드 (status 객체 또는 문자열 모두 처리 가능)
  def reply(to_status_or_acct, message, in_reply_to_id: nil)
    begin
      # status 객체인 경우
      if to_status_or_acct.respond_to?(:account)
        acct = to_status_or_acct.account.acct
        reply_to_id = in_reply_to_id || to_status_or_acct.id
      # 문자열(acct)인 경우
      else
        acct = to_status_or_acct
        reply_to_id = in_reply_to_id
      end
      
      puts "[마스토돈] → @#{acct} 에게 응답 전송"
      status_text = "@#{acct} #{message}".dup
      
      response = @client.create_status(
        status_text,
        {
          in_reply_to_id: reply_to_id,
          visibility: 'public'
        }
      )
      puts "답장 전송 완료: #{message[0..50]}..."
      response
    rescue => e
      puts "[에러] 응답 전송 실패: #{e.message}"
      puts e.backtrace.first(3)
      nil
    end
  end

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

  def self.validate_environment
    base_url = ENV['MASTODON_BASE_URL']
    token = ENV['MASTODON_TOKEN']
    
    missing_vars = []
    missing_vars << 'MASTODON_BASE_URL' if base_url.nil? || base_url.empty?
    missing_vars << 'MASTODON_TOKEN' if token.nil? || token.empty?
    
    if missing_vars.any?
      puts "필수 환경변수 누락: #{missing_vars.join(', ')}"
      puts ".env 파일을 확인해주세요."
      return false
    end
    
    true
  end

  def self.client
    @instance ||= new(
      base_url: ENV['MASTODON_BASE_URL'],
      token: ENV['MASTODON_TOKEN']
    )
  end
end
