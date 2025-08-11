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
    # 위치 관련 명령어 (통일된 형식)
    when /\[이동\/(.+?)\]/
      location = $1
      handle_move(sender, location, in_reply_to_id)
    when /\[위치확인\]/
      handle_location_check(sender, in_reply_to_id)
    when /\[주변탐색\]/
      handle_area_search(sender, in_reply_to_id)
    when /\[은신\]/
      handle_stealth(sender, in_reply_to_id)
    
    # 고급 조사 명령어 (통일된 형식)
    when /\[협력조사\/(.+?)\/@?(\w+)\]/
      target = $1
      partner = $2
      handle_cooperative_investigation(sender, target, partner, in_reply_to_id)
    when /\[방해\/@?(\w+)\]/
      target_investigator = $1
      handle_interference(sender, target_investigator, in_reply_to_id)
    when /\[물건이동\/(.+?)\/(.+?)\]/
      item = $1
      new_location = $2
      handle_item_move(sender, item, new_location, in_reply_to_id)
    when /\[숨기기\/(.+?)\/(.+?)\]/
      item = $1
      hiding_place = $2
      handle_hide_item(sender, item, hiding_place, in_reply_to_id)
    when /\[흔적조사\/(.+?)\]/
      location = $1
      handle_trace_investigation(sender, location, in_reply_to_id)
    
    # 시간 관련 명령어
    when /\[조사기록\/(.+?)\]/
      query = $1
      handle_investigation_log(sender, query, in_reply_to_id)
    when /\[타임라인\/(.+?)\]/
      item = $1
      handle_timeline(sender, item, in_reply_to_id)
    
    # 기존 조사 명령어 (통일된 형식)
    when /\[(조사|정밀조사|감지|훔쳐보기)\/(.+?)\]/
      kind = $1
      target = $2
      handle_enhanced_investigation(sender, kind, target, in_reply_to_id)
    
    # 전투 관련 명령어 (통일된 형식 추가)
    when /\[공격\/@?(\w+)\]/
      target = $1
      handle_targeted_attack(sender, target, in_reply_to_id)
    when /\[방어\/@?(\w+)\]/
      target = $1
      handle_targeted_defense(sender, target, in_reply_to_id)
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
      interference_count = 0
      cooperation_count = 0
      
      simultaneous_investigators.each do |other_id|
        if check_interference(user_id, other_id)
          interference_count += 1
          # 방해 의도 소모
          @@interference_intents.delete(user_id)
          
          # 방해자에게 알림
          interferer = @@interference_intents.dig(user_id, :interferer)
          if interferer
            @mastodon_client.dm(interferer, "#{user_id}님의 조사를 성공적으로 방해했습니다!")
          end
        end
      end
      
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

  # 방해 의도 저장 (메모리에 임시 저장)
  @@interference_intents = {}
  
  def set_interference_intent(interferer, target)
    @@interference_intents[target] = {
      interferer: interferer,
      timestamp: Time.now
    }
    
    # 5분 후 자동 만료
    Thread.new do
      sleep(300)
      @@interference_intents.delete(target) if @@interference_intents[target]&.dig(:interferer) == interferer
    end
  end

  def check_interference(target_investigator, user_id)
    intent = @@interference_intents[target_investigator]
    return false unless intent
    
    # 5분 이내의 방해 의도만 유효
    if Time.now - intent[:timestamp] <= 300
      # 방해 성공 판정
      true
    else
      @@interference_intents.delete(target_investigator)
      false
    end
  end

  def check_cooperation(cooperator_id, target_id)
    # 현재는 협력조사 명령어로만 협력 가능
    false
  end

  # 아이템 관련 헬퍼 메서드들
  def find_item_at_location(location, item_name)
    values = @sheet_manager.read_values("조사!A:K")
    return nil if values.nil? || values.empty?
    
    values.each_with_index do |row, index|
      next if index == 0
      if row[0] == item_name && row[2] == location && row[6] == "아이템"
        headers = values[0]
        result = {}
        headers.each_with_index { |header, col_index| result[header] = row[col_index] }
        return result
      end
    end
    nil
  end

  def update_item_location(item_name, new_location, mover_id)
    values = @sheet_manager.read_values("조사!A:K")
    return unless values && values.length > 1
    
    values.each_with_index do |row, index|
      next if index == 0
      if row[0] == item_name && row[6] == "아이템"
        row_num = index + 1
        timestamp = Time.now.strftime('%Y-%m-%d %H:%M:%S')
        
        # 위치(C열)와 마지막수정(J열) 업데이트
        @sheet_manager.update_values("조사!C#{row_num}", [[new_location]])
        @sheet_manager.update_values("조사!J#{row_num}", [[timestamp]])
        
        # 비고(K열)에 이동자 정보 추가
        note = "#{mover_id}이(가) #{timestamp}에 이동"
        @sheet_manager.update_values("조사!K#{row_num}", [[note]])
        break
      end
    end
  end

  def update_item_hiding(item_name, hiding_place, hiding_level, hider_id)
    values = @sheet_manager.read_values("조사!A:K")
    return unless values && values.length > 1
    
    values.each_with_index do |row, index|
      next if index == 0
      if row[0] == item_name && row[6] == "아이템"
        row_num = index + 1
        timestamp = Time.now.strftime('%Y-%m-%d %H:%M:%S')
        
        # 위치(C열), 숨김상태(H열), 마지막수정(J열) 업데이트
        @sheet_manager.update_values("조사!C#{row_num}", [[hiding_place]])
        @sheet_manager.update_values("조사!H#{row_num}", [[hiding_level]])
        @sheet_manager.update_values("조사!J#{row_num}", [[timestamp]])
        
        # 비고(K열)에 숨긴 사람 정보 추가
        note = "#{hider_id}이(가) #{timestamp}에 숨김 (숨김도:#{hiding_level})"
        @sheet_manager.update_values("조사!K#{row_num}", [[note]])
        break
      end
    end
  end

  # 조사 기록 관련 메서드들
  def get_location_investigation_history(location, limit = 10)
    values = @sheet_manager.read_values("조사로그!A:G")
    return [] if values.nil? || values.empty?
    
    headers = values[0]
    records = []
    
    values.each_with_index do |row, index|
      next if index == 0
      if row[2] == location  # 위치 열
        record = {}
        headers.each_with_index { |header, col_index| record[header] = row[col_index] }
        records << record
      end
    end
    
    # 시간순 정렬 (최신순)
    records.sort_by { |r| r["시간"] }.reverse.first(limit)
  end

  def calculate_time_ago(timestamp)
    begin
      time = Time.parse(timestamp)
      diff = Time.now - time
      
      if diff < 3600  # 1시간 미만
        minutes = (diff / 60).to_i
        "#{minutes}분 전"
      elsif diff < 86400  # 1일 미만
        hours = (diff / 3600).to_i
        "#{hours}시간 전"
      else  # 1일 이상
        days = (diff / 86400).to_i
        "#{days}일 전"
      end
    rescue
      "알 수 없는 시간"
    end
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

  # 협력조사 처리 (가상 DM방 구현)
  def handle_cooperative_investigation(user_id, target, partner, reply_id)
    # 기본 유효성 검사
    today = Date.today.to_s
    user_last_date = @sheet_manager.get_stat(user_id, "마지막조사일")
    partner_last_date = @sheet_manager.get_stat(partner, "마지막조사일")

    if user_last_date == today
      @mastodon_client.dm(user_id, "오늘은 이미 조사를 진행하셨습니다.")
      return
    end

    if partner_last_date == today
      @mastodon_client.dm(user_id, "#{partner}님은 오늘 이미 조사를 진행했습니다.")
      return
    end

    # 파트너 존재 확인
    partner_data = @sheet_manager.find_user(partner)
    unless partner_data
      @mastodon_client.dm(user_id, "#{partner}님을 찾을 수 없습니다.")
      return
    end

    # 위치 확인 (같은 장소에 있어야 함)
    user_location = get_user_location(user_id)
    partner_location = get_user_location(partner)
    
    if user_location != partner_location
      @mastodon_client.dm(user_id, "#{partner}님과 같은 장소에 있지 않습니다. (당신: #{user_location}, #{partner}: #{partner_location})")
      return
    end

    # 조사 데이터 찾기
    row = find_unified_investigation_data(target, "조사")
    unless row
      message = "#{target}에 대한 조사 정보가 없습니다."
      @mastodon_client.dm(user_id, message)
      @mastodon_client.dm(partner, message)
      return
    end

    # 협력조사 판정
    difficulty = row["난이도"].to_i
    
    # 두 사람의 행운 합산
    user_luck = (@sheet_manager.get_stat(user_id, "행운") || 0).to_i
    partner_luck = (@sheet_manager.get_stat(partner, "행운") || 0).to_i
    total_luck = (user_luck + partner_luck) / 2  # 평균값 사용
    
    # 주사위 굴리기
    dice1 = rand(1..20)
    dice2 = rand(1..20)
    best_dice = [dice1, dice2].max  # 두 주사위 중 더 좋은 결과 사용
    
    # 협력 보너스
    cooperation_bonus = 8  # 협력조사 고유 보너스
    
    # 위치 보너스
    location_bonus = location_matches_target?(user_location, target) ? 2 : 0
    
    total_result = best_dice + total_luck + cooperation_bonus + location_bonus
    success = total_result >= difficulty

    result_text = success ? row["성공결과"] : row["실패결과"]

    # 조사 기록 저장 (두 명 모두)
    log_investigation(user_id, user_location, target, "협력조사", success, result_text)
    log_investigation(partner, user_location, target, "협력조사", success, result_text)
    
    # 마지막 조사일 업데이트 (두 명 모두)
    @sheet_manager.set_stat(user_id, "마지막조사일", today)
    @sheet_manager.set_stat(partner, "마지막조사일", today)
    
    # 가상 DM방 메시지 (두 명에게 동일한 메시지 전송)
    group_message = "=== 협력조사 결과 ===\n"
    group_message += "조사자: #{user_id}, #{partner}\n"
    group_message += "대상: #{target}\n"
    group_message += "위치: #{user_location}\n\n"
    group_message += "결과: #{result_text}\n\n"
    group_message += "판정 상세:\n"
    group_message += "- #{user_id} 주사위: #{dice1}\n"
    group_message += "- #{partner} 주사위: #{dice2}\n"
    group_message += "- 채택된 주사위: #{best_dice}\n"
    group_message += "- 평균 행운: #{total_luck} (#{user_id}:#{user_luck} + #{partner}:#{partner_luck})\n"
    group_message += "- 협력 보너스: +#{cooperation_bonus}\n"
    if location_bonus > 0
      group_message += "- 위치 보너스: +#{location_bonus}\n"
    end
    group_message += "- 총합: #{total_result}/#{difficulty}"

    # 두 명 모두에게 동일한 메시지 전송 (가상 DM방 효과)
    @mastodon_client.dm(user_id, group_message)
    @mastodon_client.dm(partner, group_message)
    
    puts "[협력조사] #{user_id} + #{partner} -> #{target} (#{success ? '성공' : '실패'})"
  end

  # 방해 처리
  def handle_interference(user_id, target_investigator, reply_id)
    # 위치 확인 (같은 장소에 있어야 함)
    user_location = get_user_location(user_id)
    target_location = get_user_location(target_investigator)
    
    if user_location != target_location
      @mastodon_client.dm(user_id, "#{target_investigator}님과 같은 장소에 있지 않습니다.")
      return
    end

    # 방해 의도 기록 (임시 저장)
    set_interference_intent(user_id, target_investigator)
    
    message = "#{target_investigator}님의 조사를 방해할 준비를 했습니다. "
    message += "#{target_investigator}님이 조사를 시도하면 자동으로 방해가 적용됩니다."
    
    @mastodon_client.dm(user_id, message)
    @mastodon_client.dm(target_investigator, "누군가 당신을 주시하고 있는 것 같습니다...")
  end

  # 물건 이동 처리
  def handle_item_move(user_id, item, new_location, reply_id)
    current_location = get_user_location(user_id)
    
    # 아이템이 현재 위치에 있는지 확인
    item_data = find_item_at_location(current_location, item)
    unless item_data
      @mastodon_client.dm(user_id, "현재 위치에서 #{item}을(를) 찾을 수 없습니다.")
      return
    end

    # 숨김상태가 높으면 발견하기 어려움
    hidden_level = (item_data["숨김상태"] || 0).to_i
    if hidden_level > 50
      luck_stat = @sheet_manager.get_stat(user_id, "행운")
      luck = luck_stat ? luck_stat.to_i : 10
      detection_roll = luck + rand(1..20)
      
      if detection_roll < hidden_level
        @mastodon_client.dm(user_id, "#{item}을(를) 찾을 수 없었습니다.")
        return
      end
    end

    # 아이템 위치 업데이트
    update_item_location(item, new_location, user_id)
    
    message = "#{item}을(를) #{new_location}(으)로 이동시켰습니다."
    @mastodon_client.dm(user_id, message)
    
    # 같은 장소에 있는 다른 사람들에게 알림 (은밀도 체크)
    others_here = get_investigators_at_location(current_location).reject { |id| id == user_id }
    user_stealth = get_user_stealth(user_id)
    
    others_here.each do |other_id|
      if rand(1..20) + user_stealth < rand(1..20) + 10  # 발각 확률
        @mastodon_client.dm(other_id, "#{user_id}님이 뭔가를 옮기는 것을 보았습니다.")
      end
    end
  end

  # 물건 숨기기 처리
  def handle_hide_item(user_id, item, hiding_place, reply_id)
    current_location = get_user_location(user_id)
    
    # 아이템이 현재 위치에 있는지 확인
    item_data = find_item_at_location(current_location, item)
    unless item_data
      @mastodon_client.dm(user_id, "현재 위치에서 #{item}을(를) 찾을 수 없습니다.")
      return
    end

    # 숨기기 시도 (행운 + 민첩 기반)
    luck_stat = @sheet_manager.get_stat(user_id, "행운")
    agility_stat = @sheet_manager.get_stat(user_id, "민첩")
    
    luck = luck_stat ? luck_stat.to_i : 10
    agility = agility_stat ? agility_stat.to_i : 10
    
    hiding_roll = luck + agility + rand(1..20)
    hiding_level = [hiding_roll, 95].min  # 최대 95까지
    
    # 아이템 숨김상태 업데이트
    update_item_hiding(item, hiding_place, hiding_level, user_id)
    
    message = "#{item}을(를) #{hiding_place}에 숨겼습니다. (숨김도: #{hiding_level})"
    @mastodon_client.dm(user_id, message)
  end

  # 흔적조사 처리
  def handle_trace_investigation(user_id, location, reply_id)
    # 해당 장소의 조사 기록 조회
    investigation_history = get_location_investigation_history(location)
    
    if investigation_history.empty?
      @mastodon_client.dm(user_id, "#{location}에서 최근 조사 흔적을 찾을 수 없습니다.")
      return
    end

    # 행운 기반 흔적 발견
    luck_stat = @sheet_manager.get_stat(user_id, "행운")
    luck = luck_stat ? luck_stat.to_i : 10
    trace_roll = luck + rand(1..20)
    
    message = "#{location}의 조사 흔적:\n\n"
    
    investigation_history.each_with_index do |record, index|
      # 최근 기록일수록 발견하기 쉬움
      difficulty = 10 + (index * 3)
      
      if trace_roll >= difficulty
        time_ago = calculate_time_ago(record["시간"])
        message += "- #{time_ago} #{record["조사자"]}님이 #{record["대상"]}을(를) #{record["종류"]}함\n"
      else
        message += "- 희미한 흔적이 있지만 정확히 알 수 없음\n"
        break
      end
    end
    
    @mastodon_client.dm(user_id, message)
  end

  def handle_investigation_log(user_id, query, reply_id)
    values = @sheet_manager.read_values("조사로그!A:G")
    
    if values.nil? || values.empty?
      @mastodon_client.dm(user_id, "조사 기록이 없습니다.")
      return
    end

    headers = values[0]
    matching_records = []
    
    values.each_with_index do |row, index|
      next if index == 0
      
      # 쿼리에 따른 필터링
      case query
      when /\d{4}-\d{2}-\d{2}/  # 날짜 형식
        if row[0]&.include?(query)  # 시간 열에서 날짜 검색
          record = {}
          headers.each_with_index { |header, col_index| record[header] = row[col_index] }
          matching_records << record
        end
      when /어제/
        yesterday = (Date.today - 1).to_s
        if row[0]&.include?(yesterday)
          record = {}
          headers.each_with_index { |header, col_index| record[header] = row[col_index] }
          matching_records << record
        end
      when /오늘/
        today = Date.today.to_s
        if row[0]&.include?(today)
          record = {}
          headers.each_with_index { |header, col_index| record[header] = row[col_index] }
          matching_records << record
        end
      else  # 플레이어명으로 검색
        if row[1] == query  # 조사자 열
          record = {}
          headers.each_with_index { |header, col_index| record[header] = row[col_index] }
          matching_records << record
        end
      end
    end
    
    if matching_records.empty?
      @mastodon_client.dm(user_id, "#{query}에 대한 조사 기록을 찾을 수 없습니다.")
      return
    end
    
    # 최신순으로 정렬
    matching_records.sort_by! { |r| r["시간"] }
    matching_records.reverse!
    
    message = "=== #{query} 조사 기록 ===\n\n"
    matching_records.first(10).each do |record|  # 최대 10개
      time_ago = calculate_time_ago(record["시간"])
      message += "#{time_ago} | #{record["조사자"]} | #{record["위치"]}\n"
      message += "#{record["종류"]}: #{record["대상"]} (#{record["결과"]})\n"
      message += "결과: #{record["발견내용"]}\n\n"
    end
    
    if matching_records.length > 10
      message += "... 외 #{matching_records.length - 10}개 기록"
    end
    
    @mastodon_client.dm(user_id, message)
  end

  def handle_timeline(user_id, item, reply_id)
    # 아이템 이동 기록 조회
    item_history = get_item_timeline(item)
    investigation_history = get_item_investigation_history(item)
    
    if item_history.empty? && investigation_history.empty?
      @mastodon_client.dm(user_id, "#{item}에 대한 기록을 찾을 수 없습니다.")
      return
    end
    
    # 모든 기록을 시간순으로 합치기
    all_events = []
    
    # 아이템 이동 기록
    item_history.each do |record|
      all_events << {
        time: record["마지막수정"] || record["시간"],
        type: "이동",
        description: record["비고"] || "위치 변경",
        location: record["위치"]
      }
    end
    
    # 조사 기록
    investigation_history.each do |record|
      all_events << {
        time: record["시간"],
        type: "조사",
        description: "#{record["조사자"]}이(가) #{record["종류"]} (#{record["결과"]})",
        location: record["위치"]
      }
    end
    
    # 시간순 정렬
    all_events.sort_by! { |event| event[:time] }
    
    message = "=== #{item} 타임라인 ===\n\n"
    all_events.each do |event|
      time_ago = calculate_time_ago(event[:time])
      message += "#{time_ago} | #{event[:location]}\n"
      message += "#{event[:type]}: #{event[:description]}\n\n"
    end
    
    @mastodon_client.dm(user_id, message)
  end

  # 아이템 타임라인 조회
  def get_item_timeline(item_name)
    values = @sheet_manager.read_values("조사!A:K")
    return [] if values.nil? || values.empty?
    
    headers = values[0]
    records = []
    
    values.each_with_index do |row, index|
      next if index == 0
      if row[0] == item_name && row[6] == "아이템"
        record = {}
        headers.each_with_index { |header, col_index| record[header] = row[col_index] }
        records << record
      end
    end
    
    records
  end

  # 아이템 조사 기록 조회
  def get_item_investigation_history(item_name)
    values = @sheet_manager.read_values("조사로그!A:G")
    return [] if values.nil? || values.empty?
    
    headers = values[0]
    records = []
    
    values.each_with_index do |row, index|
      next if index == 0
      if row[3] == item_name  # 대상 열
        record = {}
        headers.each_with_index { |header, col_index| record[header] = row[col_index] }
        records << record
      end
    end
    
    records
  end

  # 전투 관련 임시 핸들러 (향후 확장 예정)
  def handle_targeted_attack(user_id, target, reply_id)
    @mastodon_client.dm(user_id, "특정 대상 공격 기능은 향후 구현될 예정입니다. 현재는 [공격] 명령어를 사용해주세요.")
  end

  def handle_targeted_defense(user_id, target, reply_id)
    @mastodon_client.dm(user_id, "특정 대상 방어 기능은 향후 구현될 예정입니다. 현재는 [방어] 명령어를 사용해주세요.")
  end
end
