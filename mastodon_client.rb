# mastodon_client.rb
# 개선된 마스토돈 클라이언트 - 스레드 출력 지원

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
    
    # 멘션 처리 기록 (중복 방지)
    @processed_mentions = Set.new
    @processed_mutex = Mutex.new
    
    puts "[봇 계정] @#{@bot_username}"
  end

  # 멘션이 이미 처리되었는지 확인
  def mention_processed?(mention_id)
    @processed_mutex.synchronize do
      @processed_mentions.include?(mention_id)
    end
  end

  # 멘션 처리 완료 기록
  def mark_mention_processed(mention_id)
    @processed_mutex.synchronize do
      @processed_mentions.add(mention_id)
      
      # 메모리 관리: 1000개 이상 쌓이면 오래된 것 삭제
      if @processed_mentions.size > 1000
        oldest = @processed_mentions.to_a.first(500)
        oldest.each { |id| @processed_mentions.delete(id) }
      end
    end
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
    puts "[마스토돈] user 스트림 구독 시작... (@#{@bot_username} 멘션 감지)"

    @streamer.user do |event|
      begin
        # Notification 이벤트만 처리
        if event.is_a?(Mastodon::Notification)
          next unless event.type == "mention"
          next unless event.status

          status = deep_symbolize(event.status.to_h)
          next unless status[:account] && status[:account][:acct]
          
          mention_id = status[:id]
          
          # 중복 처리 방지
          if mention_processed?(mention_id)
            puts "[중복 스킵] 이미 처리된 멘션: #{mention_id}"
            next
          end

          # 멘션 확인 (여러 방식으로 감지)
          has_battle_mention = false
          
          # 1. mentions 필드 확인
          if status[:mentions] && status[:mentions].any?
            has_battle_mention = status[:mentions].any? do |mention|
              username = mention[:username].to_s.downcase
              acct = mention[:acct].to_s.downcase
              username == @bot_username || acct == @bot_acct || acct.start_with?("#{@bot_username}@")
            end
          end
          
          # 2. content에서 직접 검색 (백업)
          unless has_battle_mention
            content = status[:content].to_s
            # HTML 태그 제거
            clean_content = content.gsub(/<[^>]+>/, '')
            has_battle_mention = clean_content =~ /@#{@bot_username}\b/i
          end
          
          if has_battle_mention
            puts "[멘션 감지] #{mention_id} from @#{status[:account][:acct]}"
            mark_mention_processed(mention_id)
            
            # 콜백 실행
            block.call(status)
          else
            puts "[멘션 없음] #{mention_id} - 봇 멘션이 없음"
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
      # to_status가 빈 문자열이거나 nil이면 독립 게시물로
      if to_status.nil? || to_status == "" || (to_status.is_a?(String) && to_status.empty?)
        puts "[경고] reply_status가 비어있음, 독립 게시물로 전송"
        return post(text)
      end

      status_id = to_status.is_a?(Hash) ? to_status[:id] : to_status.id
      visibility = to_status.is_a?(Hash) ? to_status[:visibility] : to_status.visibility

      unless status_id
        puts "[에러] reply: status_id가 없음"
        return nil
      end

      status_id = status_id.to_s

      # HTTP 직접 요청 사용 (gem 버그 우회)
      uri = URI("#{@base_url}/api/v1/statuses")
      request = Net::HTTP::Post.new(uri)
      request['Authorization'] = "Bearer #{@token}"
      request['Content-Type'] = 'application/json'
      request.body = {
        status: text,
        in_reply_to_id: status_id,
        visibility: visibility == "direct" ? "direct" : "public"
      }.to_json

      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
        http.request(request)
      end

      if response.code == '200'
        result = JSON.parse(response.body)
        puts "[성공] reply ID: #{result['id']}"
        return { id: result['id'].to_s }
      else
        puts "[에러] HTTP #{response.code}: #{response.body[0..200]}"
        return nil
      end
      
    rescue => e
      puts "[에러] reply 실패: #{e.class}: #{e.message}"
      puts e.backtrace.first(3)
      return nil
    end
  end

  # 스레드 형식으로 여러 메시지 전송 (새 기능)
  def reply_thread(to_status, messages)
    return nil if messages.empty?
    
    current_status = to_status
    results = []
    
    messages.each_with_index do |message, index|
      result = reply(current_status, message)
      results << result
      
      if result && result[:id]
        # 다음 메시지는 이 답글에 달기
        current_status = result
        
        # 연속 전송 시 약간의 지연 (API 제한 방지)
        sleep(0.5) if index < messages.length - 1
      else
        puts "[에러] 스레드 #{index + 1}번째 메시지 전송 실패"
        break
      end
    end
    
    results
  end

  # 스레드로 전투 결과 전송 (전투용 특화 메소드)
  def reply_battle_thread(to_status, main_message, status_message = nil, participants = [])
    messages = [main_message]
    
    if status_message && status_message.strip.length > 0
      messages << status_message
    end
    
    # 참가자 멘션 추가 (첫 번째 메시지에만)
    if participants.any?
      mention_text = participants.map { |p| "@#{p}" }.join(" ")
      messages[0] = mention_text + "\n" + messages[0]
    end
    
    reply_thread(to_status, messages)
  end

  def reply_direct(to_status, text)
    begin
      status_id = to_status.is_a?(Hash) ? to_status[:id] : to_status.id
      
      unless status_id
        puts "[에러] reply_direct: status_id가 없음"
        return nil
      end

      status_id = status_id.to_s

      uri = URI("#{@base_url}/api/v1/statuses")
      request = Net::HTTP::Post.new(uri)
      request['Authorization'] = "Bearer #{@token}"
      request['Content-Type'] = 'application/json'
      request.body = {
        status: text,
        in_reply_to_id: status_id,
        visibility: "direct"
      }.to_json

      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
        http.request(request)
      end

      if response.code == '200'
        result = JSON.parse(response.body)
        puts "[성공] direct reply ID: #{result['id']}"
        return { id: result['id'].to_s }
      else
        puts "[에러] direct reply HTTP #{response.code}: #{response.body[0..200]}"
        return nil
      end
      
    rescue => e
      puts "[에러] reply_direct 실패: #{e.class}: #{e.message}"
      puts e.backtrace.first(3)
      return nil
    end
  end

  def reply_with_mentions(to_status, text, mention_users = [])
    return reply(to_status, text) if mention_users.empty?
    
    mention_text = mention_users.map { |user| "@#{user}" }.join(" ")
    full_text = "#{mention_text}\n#{text}"
    
    reply(to_status, full_text)
  end

  def post(text, visibility: 'public')
    begin
      uri = URI("#{@base_url}/api/v1/statuses")
      request = Net::HTTP::Post.new(uri)
      request['Authorization'] = "Bearer #{@token}"
      request['Content-Type'] = 'application/json'
      request.body = {
        status: text,
        visibility: visibility
      }.to_json

      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
        http.request(request)
      end

      if response.code == '200'
        result = JSON.parse(response.body)
        puts "[성공] post ID: #{result['id']}"
        return { id: result['id'].to_s }
      else
        puts "[에러] post HTTP #{response.code}: #{response.body[0..200]}"
        return nil
      end
      
    rescue => e
      puts "[에러] post 실패: #{e.class}: #{e.message}"
      puts e.backtrace.first(3)
      return nil
    end
  end

  # 글자 수 제한을 고려한 메시지 분할
  def split_message_for_thread(message, max_length = 450)
    return [message] if message.length <= max_length
    
    parts = []
    current_part = ""
    
    message.split("\n").each do |line|
      if (current_part + line + "\n").length > max_length
        if current_part.length > 0
          parts << current_part.strip
          current_part = line + "\n"
        else
          # 한 줄이 너무 긴 경우 강제로 분할
          while line.length > max_length
            parts << line[0..max_length-1]
            line = line[max_length..-1]
          end
          current_part = line + "\n"
        end
      else
        current_part += line + "\n"
      end
    end
    
    parts << current_part.strip if current_part.length > 0
    parts
  end

  # 전투 결과 전용 스레드 출력 (글자 수 제한 고려)
  def reply_battle_result(to_status, result_message, hp_message, participants = [])
    # 메시지들을 적절한 크기로 분할
    result_parts = split_message_for_thread(result_message, 450)
    hp_parts = split_message_for_thread(hp_message, 450)
    
    all_parts = result_parts + hp_parts
    
    # 참가자 멘션은 첫 번째 파트에만 추가
    if participants.any?
      mention_text = participants.map { |p| "@#{p}" }.join(" ")
      all_parts[0] = mention_text + "\n" + all_parts[0]
    end
    
    reply_thread(to_status, all_parts)
  end

  private

  def deep_symbolize(obj)
    case obj
    when Hash
      obj.transform_keys(&:to_sym).transform_values { |v| deep_symbolize(v) }
    when Array
      obj.map { |v| deep_symbolize(v) }
    else
      obj
    end
  end
end

# 전투 전용 메시지 포맷터 클래스
class BattleMessageFormatter
  class << self
    def format_2v2_round_result(round_data)
      message = "라운드 #{round_data[:round]} 결과\n"
      message += "━━━━━━━━━━━━━━━━━━\n\n"
      
      round_data[:actions].each do |action_result|
        message += action_result + "\n\n"
      end
      
      message.strip
    end

    def format_hp_status(teams_data)
      message = "━━━━━━━━━━━━━━━━━━\n"
      message += "체력 현황\n"
      message += "━━━━━━━━━━━━━━━━━━\n"
      
      teams_data.each_with_index do |(team_name, members), index|
        message += "#{team_name}:\n"
        
        members.each do |member|
          status = member[:hp] > 0 ? "생존" : "전투불능"
          message += "• #{member[:name]}: #{member[:hp]}HP (#{status})\n"
        end
        
        message += "\n" if index < teams_data.length - 1
      end
      
      message.strip
    end

    def format_time_warning(remaining_time)
      if remaining_time > 60
        minutes = (remaining_time / 60).to_i
        "전투 종료까지 #{minutes}분 남았습니다!"
      else
        "전투 종료까지 #{remaining_time}초 남았습니다!"
      end
    end

    def format_timeout_message(user_name, action = "방어")
      "시간 초과!\n#{user_name}이(가) 4분 내에 행동하지 않아 자동으로 #{action}합니다."
    end
  end
end
