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
    puts e.backtrace.first(5)
    @mastodon_client.reply(reply_id, "조사 처리 중 오류가 발생했습니다. 잠시 후 다시 시도해주세요.", visibility: 'direct')
  end

  private

  # 1️⃣ 조사 시작
  def start_investigation(user_id, reply_id)
    user = @sheet_manager.find_user(user_id)
    unless user
      @mastodon_client.reply(reply_id, "등록되지 않은 사용자입니다. [입학/이름]으로 등록해주세요.", visibility: 'direct')
      return
    end

    locations = @sheet_manager.available_locations
    if locations.empty?
      @mastodon_client.reply(reply_id, "현재 조사 가능한 위치가 없습니다.", visibility: 'unlisted')
      return
    end

    msg = "조사를 시작합니다.\n"
    msg += "탐색 가능한 장소 목록:\n"
    msg += locations.map { |loc| "- [조사/#{loc}]" }.join("\n")
    @mastodon_client.reply(reply_id, msg, visibility: 'unlisted')
  end

  # 2️⃣ 위치 조사
  def handle_location(location, user_id, reply_id)
    unless @sheet_manager.is_location?(location)
      @mastodon_client.reply(reply_id, "#{location}은(는) 조사 가능한 위치가 아닙니다.", visibility: 'unlisted')
      return
    end

    detail_targets = @sheet_manager.find_details_in_location(location)
    if detail_targets.any?
      msg = "#{location}입니다.\n"
      msg += "이곳에서 조사할 수 있는 대상:\n"
      msg += detail_targets.map { |t| "- [세부조사/#{t}]" }.join("\n")
    else
      msg = "#{location}입니다.\n이곳에서는 아직 조사할 수 있는 대상이 없습니다."
    end

    @sheet_manager.update_investigation_state(user_id, "진행중", location)
    @mastodon_client.reply(reply_id, msg + "\n\n조사를 마치면 [조사종료]를 입력하세요.", visibility: 'unlisted')
  end

  # 3️⃣ 세부 조사
  def handle_detail(target, user_id, reply_id)
    state = @sheet_manager.get_investigation_state(user_id)
    if state["조사상태"] != "진행중"
      @mastodon_client.reply(reply_id, "먼저 [조사/장소]로 위치를 지정해주세요.", visibility: 'unlisted')
      return
    end

    location = state["위치"]
    row = @sheet_manager.find_investigation_entry(target, "정밀조사")

    unless row
      @mastodon_client.reply(reply_id, "지금은 #{target}을(를) 조사할 수 없습니다. 다시 시도해보세요.", visibility: 'unlisted')
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

    result_text = "판정: #{dice} + 행운 #{luck} = #{total} (난이도 #{difficulty})\n"
    result_text += success ? "성공\n" : "실패\n"
    result_text += result.to_s.strip
    @mastodon_client.reply(reply_id, result_text, visibility: 'unlisted')

    @sheet_manager.log_investigation(user_id, location, target, "정밀조사", success, result)
  end

  # 4️⃣ 조사 종료
  def end_investigation(user_id, reply_id)
    @sheet_manager.update_investigation_state(user_id, "없음", "-")
    @mastodon_client.reply(reply_id, "조사를 종료했습니다.", visibility: 'unlisted')
  end
end
