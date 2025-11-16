# commands/investigate_command.rb
require 'date'
require 'time'

class InvestigateCommand
  DAILY_MOVE_LIMIT = 3

  def initialize(mastodon_client, sheet_manager)
    @mastodon_client = mastodon_client
    @sheet_manager = sheet_manager
  end

  def execute(text, user_id, reply_id)
    case text
    when /\[조사시작\]/i
      start_investigation(user_id, reply_id)
    when /\[조사\/(.+)\]/i
      handle_location($1.strip, user_id, reply_id)
    when /\[세부조사\/(.+)\]/i
      handle_detail($1.strip, user_id, reply_id)
    when /\[이동\/(.+)\]/i
      move_to_location($1.strip, user_id, reply_id)
    when /\[위치확인\]/i
      check_location(user_id, reply_id)
    when /\[협력조사\/(.+)\/@(.+)\]/i
      cooperate_investigation($1.strip, $2.strip, user_id, reply_id)
    when /\[방해\/@(.+)\]/i
      disturb_investigation($1.strip, user_id, reply_id)
    when /\[조사종료\]/i
      end_investigation(user_id, reply_id)
    else
      @mastodon_client.reply(
        reply_id,
        "가능한 명령:\n" \
        "[조사시작], [조사/위치], [세부조사/대상], [이동/위치], [위치확인], [협력조사/대상/@상대], [방해/@상대], [조사종료]",
        visibility: 'unlisted'
      )
    end
  rescue => e
    puts "[에러] 조사 처리 중 오류: #{e.message}"
    puts e.backtrace.first(5)
    @mastodon_client.reply(reply_id, "조사 처리 중 오류가 발생했습니다. 잠시 후 다시 시도해주세요.", visibility: 'direct')
  end

  private

  def normalize_location(s)
    s.to_s.strip.gsub(/\p{Cf}/, '') # 공백/제어문자 제거
  end

  # === [조사시작]
  def start_investigation(user_id, reply_id)
    user = @sheet_manager.find_user(user_id)
    unless user
      @mastodon_client.reply(reply_id, "등록되지 않은 사용자입니다. [입학/이름]으로 등록해주세요.", visibility: 'direct')
      return
    end

    locations = @sheet_manager.available_locations
    msg = "조사를 시작합니다.\n탐색 가능한 장소 목록:\n"
    msg += locations.map { |loc| "- [조사/#{loc}]" }.join("\n")
    @mastodon_client.reply(reply_id, msg, visibility: 'unlisted')
  end

  # === [조사/위치]
  def handle_location(location, user_id, reply_id)
    unless @sheet_manager.is_location?(location)
      @mastodon_client.reply(reply_id, "#{location}은(는) 조사 가능한 위치가 아닙니다.", visibility: 'unlisted')
      return
    end

    @sheet_manager.update_investigation_state(user_id, "진행중", location)

    overview = @sheet_manager.location_overview_outputs(location)
    details  = @sheet_manager.detail_candidates(location)

    msg = ""

    if overview.any?
      overview.each_with_index { |line, i| msg += "#{line}\n" }
    end

    if details.any?
      msg += "\n이곳에서 조사할 수 있는 대상:\n"
      details.each { |d| msg += "- [세부조사/#{d}]\n" }
    else
      msg += "\n이곳에서는 아직 조사할 수 있는 대상이 없습니다.\n"
    end

    msg += "\n조사를 마치면 [조사종료]를 입력하세요."
    @mastodon_client.reply(reply_id, msg.strip, visibility: 'unlisted')
  end

  def handle_detail(target, user_id, reply_id)
  state = @sheet_manager.get_investigation_state(user_id)
  if state["조사상태"] != "진행중"
    @mastodon_client.reply(reply_id, "먼저 [조사/장소]로 위치를 지정해주세요.", visibility: 'unlisted')
    return
  end

  location = state["위치"]
  row = @sheet_manager.find_investigation_entry(target, "정밀조사")
  unless row
    @mastodon_client.reply(reply_id, "지금은 #{target}을(를) 조사할 수 없습니다.", visibility: 'unlisted')
    return
  end

  user = @sheet_manager.find_user(user_id)
  luck = (user["행운"] || 0).to_i

  dice = rand(1..20)
  difficulty = row["난이도"].to_i

  # 방해 디버프 확인 (F열 상태효과 값)
  status_effect = state["협력상태"].to_s.strip
  debuff = 0
  if status_effect == "방해"
    debuff = -3
    @sheet_manager.clear_status_effect(user_id)  # 1회성이라 바로 제거
  end

  total = dice + luck + debuff
  success = total >= difficulty
  result  = success ? row["성공결과"] : row["실패결과"]

  @mastodon_client.reply(
    reply_id,
    "#{target} 조사 중...\n(난이도: #{difficulty})",
    visibility: 'unlisted'
  )
  sleep 2

  msg = "판정: #{dice} + 행운 #{luck}"
  msg += " #{debuff}" if debuff != 0   # 여기서 -3이 보이는지로 확인
  msg += " = #{total} (난이도 #{difficulty})\n"
  msg += success ? "성공\n" : "실패\n"
  msg += result.to_s.strip

  @mastodon_client.reply(reply_id, msg, visibility: 'unlisted')
  @sheet_manager.log_investigation(user_id, location, target, "정밀조사", success, result)
end

  # === [이동/위치]
  def move_to_location(location, user_id, reply_id)
    state = @sheet_manager.get_investigation_state(user_id)
    unless @sheet_manager.is_location?(location)
      @mastodon_client.reply(reply_id, "#{location}은(는) 이동할 수 있는 위치가 아닙니다.", visibility: 'unlisted')
      return
    end

    points = state["이동포인트"].to_i
    if points <= 0
      @mastodon_client.reply(reply_id, "이동 포인트가 부족합니다. (하루 3회 한정, 자정에 초기화)", visibility: 'unlisted')
      return
    end

    new_points = points - 1
    @sheet_manager.update_move_points(user_id, new_points)
    @sheet_manager.update_investigation_state(user_id, "진행중", location)

    @mastodon_client.reply(reply_id, "#{location}(으)로 이동했습니다. 남은 이동 포인트: #{new_points}/3", visibility: 'unlisted')
  end

  # === [위치확인]
  def check_location(user_id, reply_id)
    state = @sheet_manager.get_investigation_state(user_id)
    location = state["위치"] || "-"
    points = state["이동포인트"] || 0
    @mastodon_client.reply(reply_id, "현재 위치: #{location}\n남은 이동 포인트: #{points}/3", visibility: 'unlisted')
  end

  # === [협력조사/대상/@상대]
  def cooperate_investigation(target, partner_name, user_id, reply_id)
    partner_id = partner_name  # "@ 테스트 방지"

    # === 상태 읽기 ===
    state         = @sheet_manager.get_investigation_state(user_id)
    partner_state = @sheet_manager.get_investigation_state(partner_id)

    # 조사상태 확인
    if state["조사상태"] != "진행중"
      @mastodon_client.reply(reply_id, "당신은 아직 조사 중이 아닙니다.", visibility: 'unlisted')
      return
    end

    if partner_state["조사상태"] != "진행중"
      @mastodon_client.reply(reply_id, "상대(@#{partner_name})는 현재 조사 중이 아닙니다.", visibility: 'unlisted')
      return
    end

    # === 위치 비교 ===
    loc1 = normalize_location(state["위치"])
    loc2 = normalize_location(partner_state["위치"])
    if loc1 != loc2
      @mastodon_client.reply(reply_id, "같은 위치에 있어야 협력 조사 가능합니다.", visibility: 'unlisted')
      return
    end

    # === 조사 데이터 로드 ===
    row = @sheet_manager.find_investigation_entry(target, "정밀조사")
    unless row
      @mastodon_client.reply(reply_id, "이곳에서 #{target}은(는) 협력 조사할 수 없습니다.", visibility: 'unlisted')
      return
    end

    # === 행운 +5 보너스 (이번 턴만) ===
    user = @sheet_manager.find_user(user_id)
    partner_user = @sheet_manager.find_user(partner_id)

    base_luck = (user["행운"] || 0).to_i + (partner_user["행운"] || 0).to_i
    temp_luck = base_luck + 5  # ← sheet에 반영 ❌ / 이번 판정에만 적용 ⭕️

    dice = rand(1..20)
    difficulty = row["난이도"].to_i
    total = dice + temp_luck
    success = total >= difficulty
    result = success ? row["성공결과"] : row["실패결과"]

    # === 출력 ===
    msg = [
      "@#{user_id}x@#{partner_name} 협력 조사!",
      "조사 위치: #{loc1}",
      "대상: #{target}",
      "",
      "주사위: #{dice}",
      "행운(협력 포함): #{temp_luck} (기본 #{base_luck} + 협력보너스 5)",
      "최종 값: #{total} vs 난이도 #{difficulty}",
      "",
      (success ? "성공!" : "실패..."),
      result.to_s.strip
    ].join("\n")

    @mastodon_client.reply(reply_id, msg, visibility: 'unlisted')

    # === 로그 기록 ===
    @sheet_manager.log_investigation(user_id,    loc1, target, "협력조사", success, result)
    @sheet_manager.log_investigation(partner_id, loc1, target, "협력조사", success, result)
  end


  # === [방해/@상대]
  def disturb_investigation(target_user, user_id, reply_id)
    target_id = target_user  # "@ 안 붙이고, SheetManager 쪽 normalize에 맡김"

    state        = @sheet_manager.get_investigation_state(user_id)
    target_state = @sheet_manager.get_investigation_state(target_id)

    if state["조사상태"] != "진행중"
      @mastodon_client.reply(reply_id, "당신은 아직 조사 중이 아닙니다.", visibility: 'unlisted')
      return
    end

    if target_state["조사상태"] != "진행중"
      @mastodon_client.reply(reply_id, "상대(@#{target_user})는 현재 조사 중이 아닙니다.", visibility: 'unlisted')
      return
    end

    if normalize_location(state["위치"]) != normalize_location(target_state["위치"])
      @mastodon_client.reply(reply_id, "같은 위치에 있어야 방해할 수 있습니다.", visibility: 'unlisted')
      return
    end

    # 여기서 F열 상태효과에 "방해" 기록
    @sheet_manager.set_status_effect(target_id, "방해")

    @mastodon_client.reply(
      reply_id,
      "@#{target_user}의 다음 조사 판정에 -3 불이익을 주었습니다! (1회 한정)",
      visibility: 'unlisted'
    )
  end


  # === [조사종료]
  def end_investigation(user_id, reply_id)
    @sheet_manager.update_investigation_state(user_id, "없음", "-")
    @mastodon_client.reply(reply_id, "조사를 종료했습니다.", visibility: 'unlisted')
  end
end
