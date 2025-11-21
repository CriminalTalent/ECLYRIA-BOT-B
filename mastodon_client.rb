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
    
    @streamer.user do |message|
      begin
        # 스트리밍 데이터는 "event: update\ndata: {...}" 형식
        next unless message.is_a?(String)
        
        lines = message.split("\n")
        event_type = nil
        data_json = nil
        
        lines.each do |line|
          if line.start_with?('event:')
            event_type = line.sub('event:', '').strip
          elsif line.start_with?('data:')
            data_json = line.sub('data:', '').strip
          end
        end
        
        next unless event_type && data_json
        
        data = JSON.parse(data_json, symbolize_names: true)
        
        # ---- 1) update 이벤트 (새 포스트) ----
        if event_type == 'update'
          status = data
          next unless status
          
          # DM 처리 - visibility가 direct인 경우
          if status[:visibility] == "direct"
            block.call(status)
            next
          end
          
          # 멘션이 들어있는 public 토트 처리
          if status[:mentions] && status[:mentions].any?
            block.call(status)
            next
          end
        end
        
        # ---- 2) notification 이벤트 (멘션 알림) ----
        if event_type == 'notification'
          notification = data
          next unless notification[:type] == "mention"
          next unless notification[:status]
          
          # 멘션 알림의 status 전달
          block.call(notification[:status])
          next
        end
        
      rescue JSON::ParserError => e
        # JSON 파싱 실패는 조용히 넘어감 (heartbeat 등)
      rescue => e
        puts "[스트리밍 처리 오류] #{e.class}: #{e.message}"
      end
    end
  end

  # ==========================================
  #  toot 또는 DM reply
  # ==========================================
  def reply(to_status, text)
    begin
      # to_status가 해시인 경우 처리
      status_id = to_status.is_a?(Hash) ? to_status[:id] : to_status.id
      visibility = to_status.is_a?(Hash) ? to_status[:visibility] : to_status.visibility
      
      @client.create_status(
        text,
        in_reply_to_id: status_id,
        visibility: visibility == "direct" ? "direct" : "public"
      )
    rescue => e
      puts "[에러] toot 실패: #{e.message}"
    end
  end

  # ==========================================
  #  전투용 멘션 답글 (참여자 태그)
  # ==========================================
  def reply_with_mentions(to_status, text, participant_ids)
    begin
      status_id = to_status.is_a?(Hash) ? to_status[:id] : to_status.id
      
      # 참여자들을 @로 태그
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
end
