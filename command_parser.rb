# command_parser.rb
class CommandParser
  def initialize(mastodon_client, battle_engine)
    @mastodon_client = mastodon_client
    @battle_engine = battle_engine
    puts "[파서] 초기화 완료"
  end

  def parse(status)
    sender = status[:account][:acct]
    content = status[:content]

    # HTML 태그 제거
    puts "[파서] 원본 HTML: #{content[0..150]}"
    clean_text = content.gsub(/<[^>]+>/, ' ').gsub(/\s+/, ' ').strip
    puts "[파서] HTML 제거: #{clean_text}"

    # 대괄호 내용 추출
    bracket_content = extract_bracket_content(clean_text)
    return unless bracket_content

    puts "[파서] 대괄호 내용: #{bracket_content}"

    # 슬래시로 분리
    parts = bracket_content.split('/')
    command = parts[0].strip
    params = parts[1..-1].map(&:strip).reject(&:empty?) if parts.length > 1
    params ||= []

    puts "[파서] 명령어: #{command}"
    puts "[파서] 파라미터: #{params.inspect}"

    # 본문에서 멘션 추출 (@로 시작하는 것들)
    mentions = clean_text.scan(/@(\w+)/).flatten.reject { |m| m == 'Battle' }
    puts "[파서] 본문 멘션: #{mentions.inspect}"

    # --------------------
    # 명령어 처리
    # --------------------
    if command =~ /^전투개시$/i
      # 파라미터에서 멘션 추출 (@ 제거)
      participants = params.map { |p| p.gsub('@', '') }

      # 파라미터가 없으면 본문 멘션 사용
      if participants.empty?
        participants = mentions
      end

      @battle_engine.start_pvp(status, participants)

    elsif command =~ /^공격$/i
      # 팀전: [공격/대상], 1:1: [공격]
      target = params[0]&.gsub('@', '')
      @battle_engine.attack(sender, status, target)

    elsif command =~ /^방어$/i
      # 팀전 대리방어: [방어/아군], 셀프: [방어]
      target = params[0]&.gsub('@', '')
      @battle_engine.defend(sender, status, target)

    elsif command =~ /^반격$/i
      @battle_engine.counter(sender, status)

    # ✅ 물약 (새 규칙)
    elsif command =~ /^물약$/i
      if params.length >= 1
        potion_size = params[0] # 소형/중형/대형
        target = params[1]&.gsub('@', '') if params.length >= 2
        @battle_engine.use_potion(sender, status, potion_size, target)
      else
        @mastodon_client.reply(
          status,
          "사용법: [물약/크기] 또는 [물약/크기/대상]\n" \
          "크기: 소형/중형/대형\n" \
          "예: [물약/소형] / [물약/중형/@아군] / [물약/대형/아군]"
        )
      end

    elsif command =~ /^체력확인$/i
      @battle_engine.check_hp(sender, status)

    elsif command =~ /^전투중단$/i
      @battle_engine.stop_battle(sender, status)

    elsif command =~ /^전투종료$/i
      @battle_engine.stop_battle(sender, status)

    else
      puts "[파서] 알 수 없는 명령어: #{command}"
    end

  rescue => e
    puts "[파서 오류] #{e.message}"
    puts e.backtrace
  end

  private

  def extract_bracket_content(text)
    match = text.match(/\[([^\]]+)\]/)
    match ? match[1] : nil
  end
end
