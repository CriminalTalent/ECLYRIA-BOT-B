# commands/investigate_command.rb
require 'date'

class InvestigateCommand
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
    when /\[조사종료\]/i
      end_investigation(user_id, reply_id)
    else
      @mastodon_client.reply(reply_id, "가능한 명령: [조사시작], [조사/위치], [세부조사/대상], [조사종료]", visibility: 'unlisted')
    end
  rescue => e
    puts "[에러] 조사 처리 중 오류: #{e.message}"
    puts e.backtrace.first(3)
    @mastodon_client.reply(reply_id, "조사 처리 중 오류가 발생했습니다.", visibility: 'direct')
  end

  private

  # 🧭 [조사시작]
  def start_investigation(user_id, reply_id)
    user = @sheet_manager.find_user(user_id)
    unless user
      @mastodon_client.reply(reply_id, "등록되지 않은 사용자입니다. [입학/이름]으로 등록해주세요.", visibility: 'direct')
      return
    end

    state = @sheet_manager.get_investigation_state(user_id)
    if state["조사상태"] == "진행중"
      @mastodon_client.reply(reply_id, "이미 #{state['위치']}에서 조사가 진행 중입니다.", visibility: 'unlisted')
      return
    end

    # 현재 가능한 위치 목록 가져오기
    locations = @sheet_manager.available_locations
    msg = "조사를 시작합니다.\n"
    msg += "다음 중 하나를 선택하세요:\n"
    msg += locations.map { |loc| "- [조사/#{loc}]" }.join("\n")
    @mastodon_client.reply(reply_id, msg, visibility: 'unlisted')
  end

  # 📍 [조사/위치]
  def handle_location(location, user_id, reply_id)
    unless validate_user(user_id, reply_id)
      return
    end

    unless @sheet_manager.is_location?(location)
      @mastodon_client.reply(reply_id, "#{location}은(는) 조사 가능한 장소가 아닙니다.", visibility: 'unlisted')
      return
    end

    @sheet_manager.update_investigation_state(user_id, "진행중", location)
    details = @sheet_manager.find_details_in_location(location)
    msg = "#{location}에 들어왔습니다.\n"
    msg += if details.any?
              "이곳에서 조사할 수 있는 대상:\n" + details.map { |d| "- [세부조사/#{d}]" }.join("\n")
            else
              "이곳에서는 아직 조사할 수 있는 대상이 없습니다."
            end
    msg += "\n\n조사가 끝나면 [조사종료]를 입력하세요."
    @mastodon_client.reply(reply_id, msg, visibility: 'unlisted')
  end

  # 🔍 [세부조사/대상]
  def handle_detail(target, user_id, reply_id)
    state = @sheet_manager.get_investigation_state(user_id)
    if state["조사상태"] != "진행중"
      @mastodon_client.reply(reply_id, "먼저 [조사/장소]로 위치를 지정해주세요.", visibility: 'unlisted')
      return
    end

    location = state["위치"]
    row = @sheet_manager.find_investigation_entry(target, "정밀조사")
    unless row
      @mastodon_client.reply(reply_id, "#{target}은(는) 현재 조사할 수 없습니다. 다시 시도해보세요.", visibility: 'unlisted')
      return
    end

    user = @sheet_manager.find_user(user_id)
    luck = (user["행운"] || 0).to_i
    dice = rand(1..20)
    difficulty = row["난이도"].to_i
    total = dice + luck
    success = total >= difficulty
    result = success ? row["성공결과"] : row["실패결과"]

    # 출력
    @mastodon_client.reply(reply_id, "#{target} 조사 중...\n(난이도: #{difficulty})", visibility: 'unlisted')
    sleep 2
    msg = "판정: #{dice} + 행운 #{luck} = #{total} (난이도 #{difficulty})\n"
    msg += success ? "성공\n" : "실패\n"
    msg += result.to_s
    @mastodon_client.reply(reply_id, msg, visibility: 'unlisted')

    # 로그 저장
    @sheet_manager.log_investigation(user_id, location, target, "정밀조사", success, result)
  end

  # 🏁 [조사종료]
  def end_investigation(user_id, reply_id)
    @sheet_manager.update_investigation_state(user_id, "없음", "-")
    @mastodon_client.reply(reply_id, "조사를 종료했습니다.", visibility: 'unlisted')
  end

  def validate_user(user_id, reply_id)
    user = @sheet_manager.find_user(user_id)
    unless user
      @mastodon_client.reply(reply_id, "등록되지 않은 사용자입니다. [입학/이름]으로 등록해주세요.", visibility: 'direct')
      return false
    end
    true
  end
end
