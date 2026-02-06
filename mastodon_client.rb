# mastodon_client.rb
require 'mastodon'
require 'ostruct'

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
        # 멘션 알림
        yield message if message.type == 'mention'
        
      when Mastodon::Status
        # DM 확인 (visibility가 'direct'인 상태)
        if message.visibility == 'direct'
          # DM을 Notification 형태로 변환
          dm_notification = OpenStruct.new(
            type: 'mention',
            status: message
          )
          yield dm_notification
        end
      end
    end
  rescue => e
    puts "[MastodonClient] 스트리밍 오류: #{e.message}"
    puts e.backtrace[0..5]
    sleep 5
    retry
  end

  def reply(status, content, visibility: nil)
    begin
      # status에서 원본 visibility 가져오기
      original_visibility = if status.respond_to?(:visibility)
        status.visibility
      else
        status['visibility'] || status[:visibility] || 'public'
      end
      
      use_visibility = visibility || original_visibility
      
      status_id = if status.respond_to?(:id)
        status.id
      else
        status['id'] || status[:id]
      end
      
      @client.create_status(
        content,
        in_reply_to_id: status_id,
        visibility: use_visibility
      )
      puts "[MastodonClient] 응답 전송 (#{use_visibility}): #{content[0..50]}..."
    rescue => e
      puts "[MastodonClient] 응답 오류: #{e.message}"
      puts e.backtrace[0..3]
    end
  end

  def get_account
    @client.verify_credentials
  rescue => e
    puts "[MastodonClient] 계정 확인 오류: #{e.message}"
    nil
  end
end
