# commands/enhanced_investigate_command.rb
require 'date'

class EnhancedInvestigateCommand
  def initialize(mastodon_client, sheet_manager)
    @mastodon_client = mastodon_client
    @sheet_manager = sheet_manager
  end

  def handle(status)
    content = status.content.gsub(/<[^>]+>/, '').strip
    sender_full = status.account.acct
    sender = sender_full.split('@').first
    in_reply_to_id = status.id

    case content
    # 위치 관련 명령어
    when /\[이동\]\s*\[(.+?)\]/
      location = $1
      handle_move(sender, location, in_reply_to_id)
    when /\[위치확인\]/
      handle_location_check(sender, in_reply_to_id)
    when /\[주변탐색\]/
      handle_area_search(sender, in_reply_to_id)
    when /\[은신\]/
      handle_stealth(sender, in_reply_to_id)
    
    # 고급 조사 명령어
    when /\[협력조사\]\s*\[(.+?)\]\s*\[@?(\w+)\]/
      target = $1
      partner = $2
      handle_cooperative_investigation(sender, target, partner, in_reply_to_id)
    when /\[방해\]\s*\[@?(\w+)\]/
      target_investigator = $1
      handle_interference(sender, target_investigator, in_reply_to_id)
    when /\[물건이동\]\s*\[(.+?)\]\s*\[(.+?)\]/
      item = $1
      new_location = $2
      handle_item_move(sender, item, new_location, in_reply_to_id)
    when /\[숨기기\]\s*\[(.+?)\]\s*\[(.+?)\]/
      item = $1
      hiding_place = $2
      handle_hide_item(sender, item, hiding_place, in_reply_to_id)
    when /\[흔적조사\]\s*\[(.+?)\]/
      location = $1
      handle_trace_investigation(sender, location, in_reply_to_id)
    
    # 시간 관련 명령어
    when /\[조사기록\]\s*\[(.+?)\]/
      query = $1
      handle_investigation_log(sender, query, in_reply_to_id)
    when /\[타임라인\]\s*\[(.+?)\]/
      item = $1
      handle_timeline(sender, item, in_reply_to_id)
    
    # 기존 조사 명령어 (확장됨)
    when /\[(조사|정밀조사|감지|훔쳐보기)\]\s*\[(.+?)\]/
      kind = $1
      target = $2
      handle_enhanced_investigation(sender, kind, target, in_reply_to_id)
    end
  end

  private

  # 위치 이동 처리
  def handle_move(user_id, location, reply_id)
    current_location = get_user_location(user_id)
    
    # 위치 시트에 정보 업데이트
    set_user_location(user_id, location, current_location)
    
    # 같은 장소에 있는 다른 조사자들 확인
    others_here = get_investigators_at_location(location).reject { |id| id == user_id }
    
    # 장소 설명과 행동 선택지 가져오기
    location_info = get_location_info(location)
    
    message = "#{location}(으)로 이동했습니다.\n\n"
    message += "#{location_info[:description]}\n\n"
    
    if others_here.any?
      message += "현재 이곳에는 #{others_here.join(', ')}님이 있습니다.\n\n"
      
      # 마주침 이벤트 체크
      encounter_event = check_encounter_event(location, [user_id] + others_here)
      if encounter_event
        message += "#{encounter_event}\n\n"
      end
    end
    
    message += "#{location_info[:actions]}"
    
    @mastodon_client.dm(user_id, message)
    
    # 같은 장소에 있는 다른 사람들에게도 알림
    others_here.each do |other_id|
      @mastodon_client.dm(other_id, "#{user_id}님이 #{location}에 도착했습니다.")
    end
  end

  # 현재 위치 확인
  def handle_location_check(user_id, reply_id)
    location = get_user_location(user_id)
    others_here = get_investigators_at_location(location).reject { |id| id == user_id }
    
    # 장소 설명과 행동 선택지 가져오기
    location_info = get_location_info(location)
    
    message = "현재 위치: #{location}\n"
    message += "#{location_info[:description]}\n\n"
    
    if others_here.any?
      message += "함께 있는 사람: #{others_here.join(', ')}\n\n"
    end
    
    message += "#{location_info[:actions]}"
    
    @mastodon_client.dm(user_id, message)
  end

  # 주변 탐색
  def handle_area_search(user_id, reply_id)
    location = get_user_location(user_id)
    others_here = get_investigators_at_location(location).reject { |id| id == user_id }
    items_here = get_items_at_location(location)
    
    # 은밀도 체크
    stealth = get_user_stealth(user_id)
    detection_roll = rand(1..20) + stealth
    
    # 장소 설명과 행동 선택지 가져오기
    location_info = get_location_info(location)
    
    message = "#{location} 주변을 탐색합니다.\n"
    message += "#{location_info[:description]}\n\n"
    
    if others_here.any?
      if detection_roll >= 15
        message += "발견된 사람: #{others_here.join(', ')}\n"
      else
        visible_others = others_here.select { rand(1..20) >= get_user_stealth(_1) }
        if visible_others.any?
          message += "보이는 사람: #{visible_others.join(', ')}\n"
        end
      end
    end
    
    if items_here.any?
      if detection_roll >= 12
        message += "발견된 물건: #{items_here.join(', ')}\n"
      end
    end
    
    message += "\n#{location_info[:actions]}"
    
    @mastodon_client.dm(user_id, message)
  end

  # 은신 처리
  def handle_stealth(user_id, reply_id)
    luck_stat = @sheet_manager.get_stat(user_id, "행운")
    luck = luck_stat ? luck_stat.to_i : 10
    
    stealth_roll = luck + rand(1..20)
    stealth_value = [stealth_roll, 100].min
    
    set_user_stealth(user_id, stealth_value)
    
    message = "은신을 시도합니다. 은밀도: #{stealth_value}\n\n"
    if stealth_value >= 80
      message += "완벽하게 숨었습니다! 다른 조사자들이 발견하기 매우 어려울 것입니다."
    elsif stealth_value >= 50
      message += "어느 정도 숨었습니다. 주의깊게 행동하면 들키지 않을 것입니다."
    else
      message += "숨기 시도했지만 완전하지 않습니다. 조심스럽게 행동하세요."
    end
    
    @mastodon_client.dm(user_id, message)
  end

  # 강화된 조사 처리
  def handle_enhanced_investigation(user_id, kind, target, reply_id)
    # 기존 조사 제한 확인
    today = Date.today.to_s
    last_date = @sheet_manager.get_stat(user_id, "마지막조사일")

    if last_date == today
      @mastodon_client.dm(user_id, "오늘은 이미 조사를 진행하셨습니다.")
      return
    end

    # 현재 위치 확인
    location = get_user_location(user_id)
    
    # 같은 장소의 다른 조사자들 확인
    other_investigators = get_investigators_at_location(location).reject { |id| id == user_id }
    
    # 동시 조사 체크
    simultaneous_investigators = other_investigators.select do |other_id|
      other_last_investigation = get_last_investigation_time(other_id)
      other_last_investigation && (Time.now - Time.parse(other_last_investigation)) < 300 # 5분 이내
    end
    
    # 조사 데이터 찾기
    row = find_unified_investigation_data(target, kind)
    unless row
      @mastodon_client.dm(user_id, "해당 대상에 대한 #{kind} 정보가 없습니다.")
      return
    end

    # 판정 계산
    difficulty = row["난이도"].to_i
    luck_stat = @sheet_manager.get_stat(user_id, "행운")
    base_stat = luck_stat ? luck_stat.to_i : 0
    dice = rand(1..20)
    
    # 보너스/페널티 계산
    bonus = 0
    bonus_text = []
    
    # 위치 보너스 (적절한 장소에서 조사)
    if location_matches_target?(location, target)
      bonus += 2
      bonus_text << "위치 보너스 +2"
    end
    
    # 동시 조사 상호작용
    if simultaneous_investigators.any?
      interference_count = simultaneous_investigators.count { |id| check_interference(id, user_id) }
      cooperation_count = simultaneous_investigators.count { |id| check_cooperation(id, user_id) }
      
      if cooperation_count > 0
        bonus += 5
        bonus_text << "협력 보너스 +5"
      end
      
      if interference_count > 0
        bonus -= 3
        bonus_text << "방해 페널티 -3"
      end
    end
    
    # 은밀도 보너스
    stealth = get_user_stealth(user_id)
    if stealth > 50
      bonus += 3
      bonus_text << "은신 보너스 +3"
    end
    
    result_value = dice + base_stat + bonus
    
    # 결과 결정
    if result_value >= difficulty
      result_text = row["성공결과"]
      success = true
    else
      result_text = row["실패결과"]
      success = false
    end

    # 조사 기록 저장
    log_investigation(user_id, location, target, kind, success, result_text)
    
    # 마지막 조사일 업데이트
    @sheet_manager.set_stat(user_id, "마지막조사일", today)
    
    # 결과 메시지 구성
    message = "#{kind} 결과: #{result_text}\n"
    message += "(주사위: #{dice}, 보정: #{base_stat}"
    if bonus != 0
      message += ", 추가: #{bonus_text.join(', ')}"
    end
    message += ", 총합: #{result_value}/#{difficulty})"
    
    # 조사한 본인에게 DM으로 결과 전송
    @mastodon_client.dm(user_id, message)
    
    # 동시 조사자들에게 알림 DM
    simultaneous_investigators.each do |other_id|
      @mastodon_client.dm(other_id, "#{user_id}님이 #{location}에서 #{target}을(를) #{kind}하고 있습니다.")
    end
  end

  # 조사 기록 저장
  def log_investigation(user_id, location, target, kind, success, result)
    timestamp = Time.now.strftime('%Y-%m-%d %H:%M:%S')
    status = success ? "성공" : "실패"
    
    log_data = [
      [timestamp, user_id, location, target, kind, status, result]
    ]
    
    begin
      @sheet_manager.append_values("조사로그!A:G", log_data)
      puts "[조사로그] 기록 저장: #{user_id} -> #{target} (#{status})"
    rescue => e
      puts "[에러] 조사로그 저장 실패: #{e.message}"
    end
  end

  # 헬퍼 메서드들
  def get_user_location(user_id)
    values = @sheet_manager.read_values("위치!A:E")
    return "알 수 없는 장소" if values.nil? || values.empty?
    
    values.each_with_index do |row, index|
      next if index == 0 # 헤더 스킵
      if row[0]&.gsub('@', '') == user_id.gsub('@', '')
        return row[1] || "알 수 없는 장소"
      end
    end
    
    # 위치 정보가 없으면 기본값으로 설정
    set_user_location(user_id, "중앙홀", nil)
    "중앙홀"
  end

  def set_user_location(user_id, new_location, previous_location)
    values = @sheet_manager.read_values("위치!A:E")
    headers = values&.first || ["ID", "현재위치", "이전위치", "이동시간", "은밀도"]
    
    user_found = false
    values&.each_with_index do |row, index|
      next if index == 0
      if row[0]&.gsub('@', '') == user_id.gsub('@', '')
        # 기존 행 업데이트
        row_num = index + 1
        timestamp = Time.now.strftime('%Y-%m-%d %H:%M:%S')
        @sheet_manager.update_values("위치!A#{row_num}:D#{row_num}", 
          [[user_id, new_location, previous_location || row[1], timestamp]])
        user_found = true
        break
      end
    end
    
    unless user_found
      # 새 행 추가
      timestamp = Time.now.strftime('%Y-%m-%d %H:%M:%S')
      @sheet_manager.append_values("위치!A:E", 
        [[user_id, new_location, previous_location, timestamp, 0]])
    end
  end

  def get_investigators_at_location(location)
    values = @sheet_manager.read_values("위치!A:E")
    return [] if values.nil? || values.empty?
    
    investigators = []
    values.each_with_index do |row, index|
      next if index == 0
      if row[1] == location
        investigators << row[0]&.gsub('@', '')
      end
    end
    
    investigators.compact
  end

  def get_user_stealth(user_id)
    values = @sheet_manager.read_values("위치!A:E")
    return 0 if values.nil? || values.empty?
    
    values.each_with_index do |row, index|
      next if index == 0
      if row[0]&.gsub('@', '') == user_id.gsub('@', '')
        return (row[4] || 0).to_i
      end
    end
    0
  end

  def set_user_stealth(user_id, stealth_value)
    values = @sheet_manager.read_values("위치!A:E")
    return if values.nil? || values.empty?
    
    values.each_with_index do |row, index|
      next if index == 0
      if row[0]&.gsub('@', '') == user_id.gsub('@', '')
        row_num = index + 1
        @sheet_manager.update_values("위치!E#{row_num}", [[stealth_value]])
        break
      end
    end
  end

  def location_matches_target?(location, target)
    # 위치와 조사 대상이 관련있는지 확인하는 로직
    # 예: "도서관"에서 "고서" 조사 시 보너스
    location_keywords = location.downcase.split
    target_keywords = target.downcase.split
    
    (location_keywords & target_keywords).any?
  end

  def get_items_at_location(location)
    values = @sheet_manager.read_values("아이템위치!A:F")
    return [] if values.nil? || values.empty?
    
    items = []
    values.each_with_index do |row, index|
      next if index == 0
      if row[1] == location && (row[2] || 0).to_i < 50 # 숨김상태가 50 미만인 것만
        items << row[0]
      end
    end
    
    items.compact
  end

  # 장소 정보 가져오기 (시트에서)
  def get_location_info(location)
    values = @sheet_manager.read_values("장소정보!A:C")
    
    if values && values.length > 1
      values.each_with_index do |row, index|
        next if index == 0 # 헤더 스킵
        if row[0] == location
          return {
            description: row[1] || "특별한 설명이 없는 장소입니다.",
            actions: row[2] || "[조사] [정밀조사] [감지] [훔쳐보기] [은신] [이동]"
          }
        end
      end
    end
    
    # 기본값 (시트에 없는 장소)
    {
      description: "#{location}는 조용하고 평범한 장소입니다.",
      actions: "[조사] [정밀조사] [감지] [훔쳐보기] [은신] [이동] [위치확인] [주변탐색]"
    }
  end

  # 장소 정보 가져오기 (시트에서)
  def get_location_info(location)
    values = @sheet_manager.read_values("장소정보!A:C")
    
    if values && values.length > 1
      values.each_with_index do |row, index|
        next if index == 0 # 헤더 스킵
        if row[0] == location
          return {
            description: row[1] || "특별한 설명이 없는 장소입니다.",
            actions: row[2] || "[조사] [정밀조사] [감지] [훔쳐보기] [은신] [이동]"
          }
        end
      end
    end
    
    # 기본값 (시트에 없는 장소)
    {
      description: "#{location}는 조용하고 평범한 장소입니다.",
      actions: "[조사] [정밀조사] [감지] [훔쳐보기] [은신] [이동] [위치확인] [주변탐색]"
    }
  end
    values = @sheet_manager.read_values("마주침이벤트!A:E")
    return nil if values.nil? || values.empty?
    
    values.each_with_index do |row, index|
      next if index == 0
      if row[0] == location
        condition = row[1] || ""
        probability = (row[2] || 0).to_i
        
        # 조건 체크 (예: "2명 이상")
        if condition.include?("#{participants.size}명") || 
           (condition.include?("이상") && participants.size >= condition.scan(/\d+/).first.to_i)
          
          if rand(1..100) <= probability
            return row[3] # 이벤트내용 반환
          end
        end
      end
    end
    
    nil
  end

  def check_interference(interferer_id, target_id)
    # 방해 의도 체크 로직 (임시로 false 반환)
    false
  end

  def check_cooperation(cooperator_id, target_id)
    # 협력 의도 체크 로직 (임시로 false 반환)
    false
  end

  def get_last_investigation_time(user_id)
    values = @sheet_manager.read_values("조사로그!A:G")
    return nil if values.nil? || values.empty?
    
    latest_time = nil
    values.each_with_index do |row, index|
      next if index == 0
      if row[1]&.gsub('@', '') == user_id.gsub('@', '')
        time_str = row[0]
        if time_str && (latest_time.nil? || Time.parse(time_str) > Time.parse(latest_time))
          latest_time = time_str
        end
      end
    end
    
    latest_time
  end

  # 추가 구현이 필요한 메서드들 (2단계 이후)
  def handle_cooperative_investigation(user_id, target, partner, reply_id)
    @mastodon_client.dm(user_id, "협력조사 기능은 곧 구현될 예정입니다.")
  end

  def handle_interference(user_id, target_investigator, reply_id)
    @mastodon_client.dm(user_id, "방해 기능은 곧 구현될 예정입니다.")
  end

  def handle_item_move(user_id, item, new_location, reply_id)
    @mastodon_client.dm(user_id, "물건이동 기능은 곧 구현될 예정입니다.")
  end

  def handle_hide_item(user_id, item, hiding_place, reply_id)
    @mastodon_client.dm(user_id, "숨기기 기능은 곧 구현될 예정입니다.")
  end

  def handle_trace_investigation(user_id, location, reply_id)
    @mastodon_client.dm(user_id, "흔적조사 기능은 곧 구현될 예정입니다.")
  end

  def handle_investigation_log(user_id, query, reply_id)
    @mastodon_client.dm(user_id, "조사기록 기능은 곧 구현될 예정입니다.")
  end

  def handle_timeline(user_id, item, reply_id)
    @mastodon_client.dm(user_id, "타임라인 기능은 곧 구현될 예정입니다.")
  end
end
