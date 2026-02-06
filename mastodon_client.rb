# mastodon_client.rb
# 스트리밍 연결 오류 해결 버전

class MastodonClient
  def initialize(base_url, access_token)
    require 'mastodon'
    @client = Mastodon::REST::Client.new(
      base_url: base_url,
      bearer_token: access_token
    )
    @streaming = Mastodon::Streaming::Client.new(
      base_url: base_url,
      bearer_token: access_token
    )
    puts "[MastodonClient] 초기화 완료"
  end

  def stream(&block)
    retry_count = 0
    max_retries = 10
    
    loop do
      begin
        puts "[MastodonClient] 스트리밍 연결 시작... (시도 #{retry_count + 1}/#{max_retries + 1})"
        @streaming.user do |notification|
          retry_count = 0  # 성공하면 재시도 카운터 리셋
          block.call(notification)
        end
      rescue => e
        retry_count += 1
        puts "[MastodonClient] 스트리밍 오류 #{retry_count}/#{max_retries + 1}: #{e.message}"
        
        if retry_count <= max_retries
          sleep_time = [retry_count * 2, 60].min  # 점진적으로 대기 시간 증가, 최대 60초
          puts "[MastodonClient] #{sleep_time}초 후 재연결 시도..."
          sleep(sleep_time)
          
          # 새로운 스트리밍 클라이언트 생성
          begin
            @streaming = Mastodon::Streaming::Client.new(
              base_url: @streaming.base_url,
              bearer_token: @streaming.bearer_token
            )
          rescue => init_error
            puts "[MastodonClient] 스트리밍 클라이언트 재초기화 오류: #{init_error.message}"
          end
        else
          puts "[MastodonClient] 최대 재시도 횟수 초과 - 5분 후 처음부터 시작"
          sleep(300)  # 5분 대기
          retry_count = 0
        end
      end
    end
  end

  def reply(status, message)
    begin
      status_id = status.respond_to?(:id) ? status.id : status[:id]
      visibility = status.respond_to?(:visibility) ? status.visibility : (status[:visibility] || 'public')
      
      result = @client.create_status(
        message,
        in_reply_to_id: status_id,
        visibility: visibility
      )
      
      puts "[MastodonClient] 답글 전송: #{result.id}"
      result
    rescue => e
      puts "[MastodonClient] 답글 전송 오류: #{e.message}"
      puts e.backtrace[0..3]
      
      # 답글 전송 재시도
      sleep(1)
      begin
        result = @client.create_status(
          message,
          in_reply_to_id: status_id,
          visibility: visibility
        )
        puts "[MastodonClient] 답글 재전송 성공: #{result.id}"
        result
      rescue => retry_error
        puts "[MastodonClient] 답글 재전송도 실패: #{retry_error.message}"
        nil
      end
    end
  end

  def post(message, visibility: 'public')
    begin
      result = @client.create_status(message, visibility: visibility)
      puts "[MastodonClient] 게시물 전송: #{result.id}"
      result
    rescue => e
      puts "[MastodonClient] 게시물 전송 오류: #{e.message}"
      puts e.backtrace[0..3]
      nil
    end
  end

  # 스레드 형식으로 여러 메시지 전송
  def reply_thread(to_status, messages)
    return nil if messages.empty?
    
    current_status = to_status
    results = []
    
    messages.each_with_index do |message, index|
      result = reply(current_status, message)
      results << result
      
      if result && result.respond_to?(:id)
        # 다음 메시지는 이 답글에 달기
        current_status = result
        
        # 연속 전송 시 약간의 지연 (API 제한 방지)
        sleep(0.8) if index < messages.length - 1
      else
        puts "[MastodonClient] 스레드 #{index + 1}번째 메시지 전송 실패"
        break
      end
    end
    
    results
  end

  # 전투 결과 전용 스레드 출력
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
    
    # 글자 수 제한을 고려한 메시지 분할
    final_messages = []
    messages.each do |msg|
      if msg.length <= 450
        final_messages << msg
      else
        # 긴 메시지를 분할
        split_messages = split_message_by_lines(msg, 450)
        final_messages.concat(split_messages)
      end
    end
    
    reply_thread(to_status, final_messages)
  end

  # 글자 수 제한을 고려한 메시지 분할
  def split_message_by_lines(message, max_length = 450)
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
          current_part = line + "\n" if line.length > 0
        end
      else
        current_part += line + "\n"
      end
    end
    
    parts << current_part.strip if current_part.length > 0
    parts
  end

  # 멘션과 함께 답글
  def reply_with_mentions(status, message, mention_users = [])
    if mention_users.any?
      mention_text = mention_users.map { |user| "@#{user}" }.join(" ")
      full_message = "#{mention_text}\n#{message}"
      reply(status, full_message)
    else
      reply(status, message)
    end
  end

  # DM으로 답글
  def reply_direct(status, message)
    begin
      status_id = status.respond_to?(:id) ? status.id : status[:id]
      
      result = @client.create_status(
        message,
        in_reply_to_id: status_id,
        visibility: 'direct'
      )
      
      puts "[MastodonClient] DM 답글 전송: #{result.id}"
      result
    rescue => e
      puts "[MastodonClient] DM 답글 전송 오류: #{e.message}"
      puts e.backtrace[0..3]
      nil
    end
  end

  # 일정 시간 후 메시지 전송 (지연 전송)
  def reply_delayed(status, message, delay_seconds = 1)
    Thread.new do
      sleep(delay_seconds)
      reply(status, message)
    end
  end

  # 메시지 전송 재시도
  def reply_with_retry(status, message, max_retries = 3)
    retries = 0
    begin
      reply(status, message)
    rescue => e
      retries += 1
      if retries <= max_retries
        puts "[MastodonClient] 재시도 #{retries}/#{max_retries}: #{e.message}"
        sleep(2 ** retries)  # 지수 백오프
        retry
      else
        puts "[MastodonClient] 최대 재시도 횟수 초과: #{e.message}"
        nil
      end
    end
  end

  # 배치 메시지 전송 (여러 상태에 동일 메시지)
  def reply_batch(statuses, message)
    results = []
    statuses.each do |status|
      result = reply(status, message)
      results << result
      sleep(0.5) if result  # API 제한 방지
    end
    results
  end

  # 디버깅용: 클라이언트 상태 확인
  def status_check
    begin
      # 간단한 API 호출로 연결 상태 확인
      account = @client.verify_credentials
      {
        connected: true,
        account: account.username,
        timestamp: Time.now
      }
    rescue => e
      {
        connected: false,
        error: e.message,
        timestamp: Time.now
      }
    end
  end
end

# 전투 전용 메시지 포맷터 클래스
class BattleMessageFormatter
  class << self
    def format_round_result(round, actions_results)
      message = "라운드 #{round} 결과\n"
      message += "━━━━━━━━━━━━━━━━━━\n\n"
      
      actions_results.each do |result_text|
        message += result_text + "\n\n"
      end
      
      message.strip
    end

    def format_team_hp_status(teams)
      message = "━━━━━━━━━━━━━━━━━━\n"
      message += "체력 현황\n"
      message += "━━━━━━━━━━━━━━━━━━\n"
      
      teams.each_with_index do |(team_name, members), index|
        message += "#{team_name}:\n"
        
        members.each do |member|
          status_text = member[:hp] > 0 ? "생존" : "전투불능"
          hp_bar = generate_hp_bar(member[:hp], member[:max_hp])
          message += "• #{member[:name]}: #{hp_bar} (#{status_text})\n"
        end
        
        message += "\n" if index < teams.length - 1
      end
      
      message.strip
    end

    def format_timeout_warning(time_left)
      if time_left > 60
        minutes = (time_left / 60).to_i
        "전투 종료까지 #{minutes}분 남았습니다!"
      else
        "전투 종료까지 #{time_left}초 남았습니다!"
      end
    end

    def format_auto_action(user_name, action = "방어")
      "시간 초과! #{user_name}이(가) 4분 내에 행동하지 않아 자동으로 #{action}합니다."
    end

    def generate_hp_bar(current_hp, max_hp, bar_length = 10)
      return "█" * bar_length + " #{current_hp}/#{max_hp}" if current_hp >= max_hp
      return "░" * bar_length + " #{current_hp}/#{max_hp}" if current_hp <= 0 || max_hp <= 0
      
      filled_length = ((current_hp.to_f / max_hp.to_f) * bar_length).round
      empty_length = bar_length - filled_length
      
      "█" * filled_length + "░" * empty_length + " #{current_hp}/#{max_hp}"
    end
  end
end
