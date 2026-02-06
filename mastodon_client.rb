# mastodon_client.rb
require 'mastodon'

class MastodonClient
  attr_reader :client, :streaming_client

  def initialize(base_url, token)
    @base_url = base_url
    @token = token
    
    # REST API 클라이언트
    @client = Mastodon::REST::Client.new(
      base_url: @base_url,
      bearer_token: @token
    )
    
    # 스트리밍 클라이언트
    @streaming_client = Mastodon::Streaming::Client.new(
      base_url: @base_url,
      bearer_token: @token
    )
    
    puts "[MastodonClient] 초기화 완료: #{@base_url}"
  end

  def stream(&block)
    puts "[MastodonClient] 스트리밍 시작..."
    
    @streaming_client.user do |message|
      case message
      when Mastodon::Notification
        yield message
      when Mastodon::Status
        # 상태 업데이트 무시
      else
        # 기타 메시지 무시
      end
    end
  rescue => e
    puts "[MastodonClient] 스트리밍 오류: #{e.message}"
    puts e.backtrace[0..5]
    sleep 5
    retry
  end

  def reply(status, content)
    begin
      @client.create_status(
        content,
        in_reply_to_id: status['id'] || status[:id]
      )
      puts "[MastodonClient] 응답 전송: #{content[0..50]}..."
    rescue => e
      puts "[MastodonClient] 응답 오류: #{e.message}"
    end
  end

  def get_account
    @client.verify_credentials
  rescue => e
    puts "[MastodonClient] 계정 확인 오류: #{e.message}"
    nil
  end
end
