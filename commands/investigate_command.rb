# commands/investigate_command.rb
require 'date'

class InvestigateCommand
  def initialize(mastodon_client, sheet_manager)
    @mastodon_client = mastodon_client
    @sheet_manager = sheet_manager
  end

  def investigate(text, user_id, reply_id)
    match = text.match(/\[(조사|정밀조사|감지|훔쳐보기)\]\s*(.+)/i)
    kind = match ? match[1] : "조사"
    target = match ? match[2].strip : "불명 대상"

    user = @sheet_manager.find_user(user_id)
    unless user
      @mastodon_client.reply(reply_id, "등록되지 않은 사용자입니다. [입학/이름]으로 등록해주세요.", visibility: 'direct')
      return
    end

    # === 1️⃣ 위치 조사 (세부조사 없음) ===
    if @sheet_manager.is_location?(target)
      detail_targets = @sheet_manager.find_details_in_location(target)
      if detail_targets.any?
        msg = "#{target}입니다.\n"
        msg += "이곳에서 조사할 수 있는 대상: " + detail_targets.join(' / ')
      else
        msg = "#{target}입니다.\n이곳에서는 현재 조사할 만한 것이 없습니다."
      end
      @mastodon_client.reply(reply_id, msg, visibility: 'unlisted')
      return
    end

    # === 2️⃣ 세부조사 ===
    row = @sheet_manager.find_investigation_entry(target, kind)
    unless row
      nearby = @sheet_manager.find_related_targets(target)
      hint = nearby.any? ? "이 주변에서 조사 가능한 대상: #{nearby.join(' / ')}" : "다른 조사가 필요할 것 같습니다."
      @mastodon_client.reply(reply_id, "지금은 #{target}을(를) 조사할 수 없습니다. 다시 시도해보세요.\n#{hint}", visibility: 'unlisted')
      return
    end

    # === 3️⃣ 난이도 판정 ===
    difficulty = row["난이도"].to_i
    luck = (user["행운"] || 0).to_i
    dice = rand(1..20)
    total = luck + dice
    success = total >= difficulty
    result_text = success ? row["성공결과"] : row["실패결과"]

    # === 4️⃣ 단계별 출력 ===
    start_msg = @mastodon_client.reply(reply_id, "(#{target}) #{kind}을(를) 시작합니다...\n난이도: #{difficulty}", visibility: 'unlisted')
    sleep 2

    progress_text = case kind
                    when "정밀조사"
                      "당신은 손끝으로 천천히 표면을 더듬습니다. 작은 흔적 하나까지 놓치지 않으려는 듯 집중합니다."
                    when "감지"
                      "당신은 말을 멈추고 조용히 주변의 기류를 살핍니다. 눈으로 보이지 않는 미세한 움직임이 느껴집니다."
                    when "훔쳐보기"
                      "당신은 숨을 죽이고 시선의 각도만으로 상황을 파악합니다. 누구도 당신의 시선을 눈치채지 못합니다."
                    else
                      "당신은 주위를 천천히 훑어보며 현장의 상태를 확인합니다. 사소한 흔적 하나까지 기록하려 합니다."
                    end

    mid = @mastodon_client.reply(start_msg, progress_text, in_reply_to_id: start_msg.id, visibility: 'unlisted')
    sleep 3

    result_msg = "#{kind} 판정: #{dice} + 행운 #{luck} = #{total} (난이도 #{difficulty})\n"
    result_msg += success ? "결과: 판정 성공\n" : "결과: 판정 실패\n"
    result_msg += success ? "기록: #{result_text.to_s.strip}" : "관찰 기록: #{result_text.to_s.strip}"

    @mastodon_client.reply(mid, result_msg, in_reply_to_id: start_msg.id, visibility: 'unlisted')

    today = Time.now.strftime('%Y-%m-%d')
    @sheet_manager.update_stat(user_id, "마지막조사일", today)

    puts "[조사] #{user_id} → #{target} / #{kind} (#{success ? '성공' : '실패'})"
  rescue => e
    puts "[에러] 조사 처리 중 오류: #{e.message}"
    puts e.backtrace.first(5)
    @mastodon_client.reply(reply_id, "조사 처리 중 오류가 발생했습니다. 잠시 후 다시 시도해주세요.", visibility: 'direct')
  end
end
