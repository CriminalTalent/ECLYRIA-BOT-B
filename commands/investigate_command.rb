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
    details = @sheet_manager.find_details_in_location(location)
    msg = "#{location}입니다.\n"
    msg += if details.any?
              "이곳에서 조사할 수 있는 대상:\n" + details.map { |t| "- [세부조사/#{t}]" }.join("\n")
            else
              "이곳에서는 아직 조사할 수 있는 대상이 없습니다."
            end
    msg += "\n\n조사를 마치면 [조사종료]를 입력하세요."
    @mastodon_client.reply(reply_id, msg, visibility: 'unlisted')
  end

  # === [세부조사/대상]
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
    total = dice + luck
    success = total >= difficulty
    result = success ? row["성공결과"] : row["실패결과"]

    @mastodon_client.reply(reply_id, "#{target} 조사 중...\n(난이도: #{difficulty})", visibility: 'unlisted')
    sleep 2

    msg = "판정: #{dice} + 행운 #{luck} = #{total} (난이도 #{difficulty})\n"
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
  def cooperate_investigation(target, partner, user_id, reply_id)
    partner_id = "@#{partner}"
    state = @sheet_manager.get_investigation_state(user_id)
    partner_state = @sheet_manager.get_investigation_state(partner_id)

    if state["위치"] != partner_state["위치"]
      @mastodon_client.reply(reply_id, "같은 위치에 있어야 협력 조사를 진행할 수 있습니다.", visibility: 'unlisted')
      return
    end

    bonus = 5
    @mastodon_client.reply(reply_id, "#{partner_id}와 함께 #{target}을(를) 협력 조사합니다. 행운 보너스 +#{bonus}", visibility: 'unlisted')
  end

  # === [방해/@상대]
  def disturb_investigation(target_user, user_id, reply_id)
    target_id = "@#{target_user}"
    state = @sheet_manager.get_investigation_state(user_id)
    target_state = @sheet_manager.get_investigation_state(target_id)

    if state["위치"] != target_state["위치"]
      @mastodon_client.reply(reply_id, "같은 위치에 있어야 방해할 수 있습니다.", visibility: 'unlisted')
      return
    end

    @mastodon_client.reply(reply_id, "#{target_id}의 조사를 방해했습니다. 상대의 다음 조사 판정이 -3 불이익을 받습니다.", visibility: 'unlisted')
  end

  # === [조사종료]
  def end_investigation(user_id, reply_id)
    @sheet_manager.update_investigation_state(user_id, "없음", "-")
    @mastodon_client.reply(reply_id, "조사를 종료했습니다.", visibility: 'unlisted')
  end
end
