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

    # 조사 데이터 불러오기
    row = @sheet_manager.find_investigation_data(target, kind)
    unless row
      @mastodon_client.reply(reply_id, "#{target}에 대한 #{kind} 정보가 없습니다.", visibility: 'unlisted')
      return
    end

    difficulty = row["난이도"].to_i
    luck = (user["행운"] || 0).to_i
    dice = rand(1..20)
    total = luck + dice
    success = total >= difficulty
    result = success ? row["성공결과"] : row["실패결과"]

    # 1단계 — 시작
    first = @mastodon_client.reply(reply_id, "(#{target}) #{kind}을(를) 시작합니다...\n난이도: #{difficulty}", visibility: 'unlisted')
    sleep 2

    # 2단계 — 과정 묘사
    progress_text = case kind
                    when "정밀조사"
                      "당신은 숨을 죽이고 주변의 세부 흔적을 관찰합니다..."
                    when "감지"
                      "공기의 흐름이 미묘하게 달라집니다. 마력이 감돌고 있습니다..."
                    when "훔쳐보기"
                      "조용히 시선을 흘려 주변 상황을 파악하려 합니다..."
                    else
                      "조심스레 주위를 탐색합니다..."
                    end
    mid = @mastodon_client.reply(first, progress_text, in_reply_to_id: first.id, visibility: 'unlisted')
    sleep 3

    # 3단계 — 결과 출력
    result_text = "#{kind} 판정: #{dice} + 행운 #{luck} = #{total} (난이도 #{difficulty})\n"
    result_text += success ? "성공\n" : "실패\n"
    result_text += result.to_s.strip

    @mastodon_client.reply(mid, result_text, in_reply_to_id: first.id, visibility: 'unlisted')

    # 마지막 조사일 업데이트
    today = Time.now.strftime('%Y-%m-%d')
    @sheet_manager.update_stat(user_id, "마지막조사일", today)

    puts "[조사] #{user_id} → #{target} / #{kind} (#{success ? '성공' : '실패'})"
  rescue => e
    puts "[에러] 조사 처리 중 오류: #{e.message}"
    puts e.backtrace.first(5)
    @mastodon_client.reply(reply_id, "조사 처리 중 오류가 발생했습니다: #{e.message}", visibility: 'direct')
  end
end
