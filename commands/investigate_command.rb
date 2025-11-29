# commands/investigate_command.rb
require 'date'
require 'time'

class InvestigateCommand
  DAILY_MOVE_LIMIT = 3

  def initialize(mastodon_client, sheet_manager)
    @mastodon_client = mastodon_client
    @sheet_manager = sheet_manager
    @active_investigations = {}  # user_id => reply_status 매핑
  end

  def execute(text, user_id, reply_status)
    # 조사 중이면 저장된 reply_status 사용, 아니면 새로 저장
    if @active_investigations[user_id]
      current_reply = @active_investigations[user_id]
    else
      current_reply = reply_status
      @active_investigations[user_id] = reply_status
    end

    case text
    when /\[조사시작\]/i
      start_investigation(user_id, current_reply)
    when /\[조사\/(.+)\]/i
      handle_location($1.strip, user_id, current_reply)
    when /\[세부조사\/(.+)\]/i
      handle_detail($1.strip, user_id, current_reply)
    when /\[이동\/(.+)\]/i
      move_to_location($1.strip, user_id, current_reply)
    when /\[위치확인\]/i
      check_location(user_id, current_reply)
    when /\[협력조사\/(.+)\/@(.+)\]/i
      cooperate_investigation($1.strip, $2.strip, user_id, current_reply)
    when /\[방해\/@(.+)\]/i
      disturb_investigation($1.strip, user_id, current_reply)
    when /\[조사종료\]/i
      end_investigation(user_id, current_reply)
    else
      @mastodon_client.reply(
        current_reply,
        "가능한 명령:\n" \
        "[조사시작], [조사/위치], [세부조사/대상], [이동/위치], [위치확인], [협력조사/대상/@상대], [방해/@상대], [조사종료]"
      )
    end
  rescue => e
    puts "[에러] 조사 처리 중 오류: #{e.message}"
    puts e.backtrace.first(5)
    @mastodon_client.reply(reply_status, "조사 처리 중 오류가 발생했습니다. 잠시 후 다시 시도해주세요.")
  end

  private

  def normalize_location(s)
    s.to_s.strip.gsub(/\p{Cf}/, '')
  end

  # === [조사시작]
  def start_investigation(user_id, reply_status)
    user = @sheet_manager.find_user(user_id)
    unless user
      @mastodon_client.reply(reply_status, "등록되지 않은 사용자입니다. [입학/이름]으로 등록해주세요.")
      return
    end

    locations = @sheet_manager.available_locations
    msg = "━━━━━━━━━━━━━━━━━━\n"
    msg += "조사를 시작합니다\n"
    msg += "━━━━━━━━━━━━━━━━━━\n\n"
    msg += "탐색 가능한 장소:\n"
    msg += locations.map { |loc| "- #{loc}" }.join("\n")
    msg += "\n\n━━━━━━━━━━━━━━━━━━\n"
    msg += "[조사/위치] [위치확인] [조사종료]"
    
    # 공개 답글
    @mastodon_client.reply(reply_status, msg)
  end

  # === [조사/위치] - 개요만 공개, 세부는 DM
  def handle_location(location, user_id, reply_status)
    unless @sheet_manager.is_location?(location)
      @mastodon_client.reply(reply_status, "#{location}은(는) 조사 가능한 위치가 아닙니다.")
      return
    end

    @sheet_manager.update_investigation_state(user_id, "진행중", location)

    # 위치 정보 조회
    row = @sheet_manager.find_investigation_entry(location, "조사")
    
    if row
      # 난이도 판정
      user = @sheet_manager.find_user(user_id)
      luck = (user["행운"] || 0).to_i
      dice = rand(1..20)
      difficulty = row["난이도"].to_i
      total = dice + luck
      success = total >= difficulty
      
      # DM으로 결과 전송
      dm_msg = "━━━━━━━━━━━━━━━━━━\n"
      dm_msg += "위치: #{location}\n"
      dm_msg += "━━━━━━━━━━━━━━━━━━\n\n"
      dm_msg += "판정: #{dice} + 행운 #{luck} = #{total}\n"
      dm_msg += "난이도: #{difficulty}\n"
      dm_msg += "결과: #{success ? '성공' : '실패'}\n\n"
      dm_msg += "━━━━━━━━━━━━━━━━━━\n"
      
      result_text = success ? row["성공결과"] : row["실패결과"]
      dm_msg += result_text.to_s.strip
      dm_msg += "\n━━━━━━━━━━━━━━━━━━"
      
      @mastodon_client.dm(user_id, dm_msg)
      
      # 공개 답글은 간단하게
      public_msg = "#{location} 조사 중...\n"
      public_msg += "결과를 DM으로 전송했습니다.\n"
      public_msg += "━━━━━━━━━━━━━━━━━━\n"
      public_msg += "[세부조사/대상] [이동/위치] [위치확인] [조사종료]"
      @mastodon_client.reply(reply_status, public_msg)
      
      # 로그 기록
      @sheet_manager.log_investigation(user_id, location, location, "조사", success, result_text)
    else
      # 개요 정보만 있는 경우
      overview = @sheet_manager.location_overview_outputs(location)
      
      if overview.any?
        # DM으로 개요 전송
        dm_msg = "━━━━━━━━━━━━━━━━━━\n"
        dm_msg += "#{location}\n"
        dm_msg += "━━━━━━━━━━━━━━━━━━\n\n"
        dm_msg += overview.join("\n\n")
        dm_msg += "\n\n━━━━━━━━━━━━━━━━━━"
        
        @mastodon_client.dm(user_id, dm_msg)
      end
      
      public_msg = "#{location}을(를) 둘러봅니다.\n"
      public_msg += "결과를 DM으로 전송했습니다.\n"
      public_msg += "━━━━━━━━━━━━━━━━━━\n"
      public_msg += "[세부조사/대상] [이동/위치] [위치확인] [조사종료]"
      @mastodon_client.reply(reply_status, public_msg)
    end

    # 세부 조사 대상 안내
    details = @sheet_manager.detail_candidates(location)
    if details.any?
      detail_msg = "\n\n세부 조사 가능:\n"
      detail_msg += details.map { |d| "- [세부조사/#{d}]" }.join("\n")
      @mastodon_client.dm(user_id, detail_msg)
    end
  end

  # === [세부조사/대상] - 항상 DM으로
  def handle_detail(target, user_id, reply_status)
    state = @sheet_manager.get_investigation_state(user_id)
    if state["조사상태"] != "진행중"
      @mastodon_client.reply(reply_status, "먼저 [조사/장소]로 위치를 지정해주세요.")
      return
    end

    location = state["위치"]
    row = @sheet_manager.find_investigation_entry(target, "정밀조사")
    unless row
      @mastodon_client.reply(reply_status, "지금은 #{target}을(를) 조사할 수 없습니다.")
      return
    end

    user = @sheet_manager.find_user(user_id)
    luck = (user["행운"] || 0).to_i

    dice = rand(1..20)
    difficulty = row["난이도"].to_i

    # 방해 디버프 확인
    status_effect = state["협력상태"].to_s.strip
    debuff = 0
    if status_effect == "방해"
      debuff = -3
      @sheet_manager.clear_status_effect(user_id)
    end

    total = dice + luck + debuff
    success = total >= difficulty
    result = success ? row["성공결과"] : row["실패결과"]

    # 공개 답글
    public_msg = "#{target} 정밀 조사 중...\n"
    public_msg += "결과를 DM으로 전송합니다.\n"
    public_msg += "━━━━━━━━━━━━━━━━━━\n"
    public_msg += "[세부조사/대상] [이동/위치] [위치확인] [조사종료]"
    @mastodon_client.reply(reply_status, public_msg)

    # DM으로 상세 결과 전송
    dm_msg = "━━━━━━━━━━━━━━━━━━\n"
    dm_msg += "정밀 조사: #{target}\n"
    dm_msg += "위치: #{location}\n"
    dm_msg += "━━━━━━━━━━━━━━━━━━\n\n"
    dm_msg += "판정: #{dice} + 행운 #{luck}"
    dm_msg += " #{debuff}" if debuff != 0
    dm_msg += " = #{total}\n"
    dm_msg += "난이도: #{difficulty}\n"
    dm_msg += "결과: #{success ? '성공' : '실패'}\n\n"
    dm_msg += "━━━━━━━━━━━━━━━━━━\n"
    dm_msg += result.to_s.strip
    dm_msg += "\n━━━━━━━━━━━━━━━━━━"

    @mastodon_client.dm(user_id, dm_msg)
    
    # 로그 기록
    @sheet_manager.log_investigation(user_id, location, target, "정밀조사", success, result)
  end

  # === [이동/위치]
  def move_to_location(location, user_id, reply_status)
    state = @sheet_manager.get_investigation_state(user_id)
    unless @sheet_manager.is_location?(location)
      @mastodon_client.reply(reply_status, "#{location}은(는) 이동할 수 있는 위치가 아닙니다.")
      return
    end

    points = state["이동포인트"].to_i
    if points <= 0
      @mastodon_client.reply(reply_status, "이동 포인트가 부족합니다. (하루 3회 한정, 자정에 초기화)")
      return
    end

    new_points = points - 1
    @sheet_manager.update_move_points(user_id, new_points)
    @sheet_manager.update_investigation_state(user_id, "진행중", location)

    msg = "#{location}(으)로 이동했습니다.\n"
    msg += "남은 이동 포인트: #{new_points}/3\n"
    msg += "━━━━━━━━━━━━━━━━━━\n"
    msg += "[조사/위치] [세부조사/대상] [위치확인] [조사종료]"
    @mastodon_client.reply(reply_status, msg)
  end

  # === [위치확인]
  def check_location(user_id, reply_status)
    state = @sheet_manager.get_investigation_state(user_id)
    location = state["위치"] || "-"
    points = state["이동포인트"] || 0
    
    msg = "현재 위치: #{location}\n"
    msg += "남은 이동 포인트: #{points}/3\n"
    msg += "━━━━━━━━━━━━━━━━━━\n"
    
    if location != "-"
      msg += "[조사/위치] [세부조사/대상] [이동/위치] [조사종료]"
    else
      msg += "[조사시작] [조사/위치]"
    end
    
    @mastodon_client.reply(reply_status, msg)
  end

  # === [협력조사/대상/@상대] - DM으로
  def cooperate_investigation(target, partner_name, user_id, reply_status)
    partner_id = partner_name

    state = @sheet_manager.get_investigation_state(user_id)
    partner_state = @sheet_manager.get_investigation_state(partner_id)

    if state["조사상태"] != "진행중"
      @mastodon_client.reply(reply_status, "당신은 아직 조사 중이 아닙니다.")
      return
    end

    if partner_state["조사상태"] != "진행중"
      @mastodon_client.reply(reply_status, "상대(@#{partner_name})는 현재 조사 중이 아닙니다.")
      return
    end

    loc1 = normalize_location(state["위치"])
    loc2 = normalize_location(partner_state["위치"])
    if loc1 != loc2
      @mastodon_client.reply(reply_status, "같은 위치에 있어야 협력 조사 가능합니다.")
      return
    end

    row = @sheet_manager.find_investigation_entry(target, "정밀조사")
    unless row
      @mastodon_client.reply(reply_status, "이곳에서 #{target}은(는) 협력 조사할 수 없습니다.")
      return
    end

    user = @sheet_manager.find_user(user_id)
    partner_user = @sheet_manager.find_user(partner_id)

    base_luck = (user["행운"] || 0).to_i + (partner_user["행운"] || 0).to_i
    temp_luck = base_luck + 5

    dice = rand(1..20)
    difficulty = row["난이도"].to_i
    total = dice + temp_luck
    success = total >= difficulty
    result = success ? row["성공결과"] : row["실패결과"]

    # 공개 답글
    public_msg = "@#{user_id} x @#{partner_name} 협력 조사!\n"
    public_msg += "결과를 DM으로 전송합니다.\n"
    public_msg += "━━━━━━━━━━━━━━━━━━\n"
    public_msg += "[세부조사/대상] [협력조사/대상/@상대] [방해/@상대] [조사종료]"
    @mastodon_client.reply(reply_status, public_msg)

    # DM 메시지 생성
    dm_msg = "━━━━━━━━━━━━━━━━━━\n"
    dm_msg += "협력 조사\n"
    dm_msg += "━━━━━━━━━━━━━━━━━━\n\n"
    dm_msg += "참가자: @#{user_id} x @#{partner_name}\n"
    dm_msg += "위치: #{loc1}\n"
    dm_msg += "대상: #{target}\n\n"
    dm_msg += "판정: #{dice}\n"
    dm_msg += "행운: #{temp_luck} (기본 #{base_luck} + 협력 +5)\n"
    dm_msg += "최종: #{total} vs 난이도 #{difficulty}\n"
    dm_msg += "결과: #{success ? '성공' : '실패'}\n\n"
    dm_msg += "━━━━━━━━━━━━━━━━━━\n"
    dm_msg += result.to_s.strip
    dm_msg += "\n━━━━━━━━━━━━━━━━━━"

    # 양쪽 모두에게 DM 전송
    @mastodon_client.dm(user_id, dm_msg)
    @mastodon_client.dm(partner_id, dm_msg)

    # 로그 기록
    @sheet_manager.log_investigation(user_id, loc1, target, "협력조사", success, result)
    @sheet_manager.log_investigation(partner_id, loc1, target, "협력조사", success, result)
  end

  # === [방해/@상대]
  def disturb_investigation(target_user, user_id, reply_status)
    target_id = target_user

    state = @sheet_manager.get_investigation_state(user_id)
    target_state = @sheet_manager.get_investigation_state(target_id)

    if state["조사상태"] != "진행중"
      @mastodon_client.reply(reply_status, "당신은 아직 조사 중이 아닙니다.")
      return
    end

    if target_state["조사상태"] != "진행중"
      @mastodon_client.reply(reply_status, "상대(@#{target_user})는 현재 조사 중이 아닙니다.")
      return
    end

    if normalize_location(state["위치"]) != normalize_location(target_state["위치"])
      @mastodon_client.reply(reply_status, "같은 위치에 있어야 방해할 수 있습니다.")
      return
    end

    @sheet_manager.set_status_effect(target_id, "방해")

    # 공개 답글
    msg = "@#{target_user}을(를) 방해했습니다!\n"
    msg += "━━━━━━━━━━━━━━━━━━\n"
    msg += "[세부조사/대상] [협력조사/대상/@상대] [방해/@상대] [조사종료]"
    @mastodon_client.reply(reply_status, msg)

    # 방해받은 사람에게 DM
    @mastodon_client.dm(
      target_id,
      "━━━━━━━━━━━━━━━━━━\n" \
      "방해 경고\n" \
      "━━━━━━━━━━━━━━━━━━\n\n" \
      "@#{user_id}에게 방해를 받았습니다!\n" \
      "다음 조사 판정에 -3 불이익이 적용됩니다.\n" \
      "━━━━━━━━━━━━━━━━━━"
    )
  end

  # === [조사종료]
  def end_investigation(user_id, reply_status)
    @sheet_manager.update_investigation_state(user_id, "없음", "-")
    @active_investigations.delete(user_id)  # 스레드 정보 삭제
    @mastodon_client.reply(reply_status, "조사를 종료했습니다.")
  end
end
