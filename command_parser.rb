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
    mentions = clean_text.scan(/@([A-Za-z0-9_]+)/).flatten.reject { |m| m.downcase == 'battle' }
    puts "[파서] 본문 멘션: #{mentions.inspect}"

    # 파라미터 -> 참가자 정규화
    participants_from_params = params.map { |p| normalize_id(p) }.compact.reject(&:empty?)

    # 파라미터가 없으면 본문 멘션 사용
    participants = participants_from_params
    participants = mentions.map { |m| normalize_id(m) }.compact.reject(&:empty?) if participants.empty?

    # --------------------
    # 전투 시작 명령 분리
    # --------------------

    # ✅ 1:1 전투 시작 (반드시 2명)
    if command =~ /^전투개시$/i
      if participants.length != 2
        @mastodon_client.reply(
          status,
          "❗ [전투개시]는 1:1 전용입니다.\n" \
          "사용법: [전투개시/@A/@B]\n" \
          "다인전투는: [다인전투/@A/@B/@C/@D...]"
        )
        return
      end

      @battle_engine.start_pvp(status, participants)  # 기존 엔진 흐름 유지
      return
    end

    # ✅ 다인전투 시작 (3명 이상)  ※ 4명 이상으로 강제하고 싶으면 3을 4로 바꿔줘
    if command =~ /^다인전투$/i
      if participants.length < 3
        @mastodon_client.reply(
          status,
          "❗ [다인전투]는 3명 이상 필요합니다.\n" \
          "사용법: [다인전투/@A/@B/@C/@D...]"
        )
        return
      end

      @battle_engine.start_pvp(status, participants)  # 일단 같은 시작 루틴 사용
      return
    end

    # --------------------
    # 행동 명령
    # --------------------

    # 공격
    if command =~ /^공격$/i
      target = normalize_id(params[0])
      @battle_engine.attack(sender, status, target)

    # 방어
    elsif command =~ /^방어$/i
      target = normalize_id(params[0])
      @battle_engine.defend(sender, status, target)

    # 반격
    elsif command =~ /^반격$/i
      @battle_engine.counter(sender, status)

    # 물약사용
    elsif command =~ /^물약사용$/i
      if params.length >= 1
        potion_size = params[0]
        target = normalize_id(params[1]) if params.length >= 2
        @battle_engine.use_potion(sender, status, potion_size, target)
      else
        @mastodon_client.reply(
          status,
          "사용법: [물약사용/크기] 또는 [물약사용/크기/@타겟]\n" \
          "예: [물약사용/소형] 또는 [물약사용/중형/@아군]"
        )
      end

    # 체력확인
    elsif command =~ /^체력확인$/i
      @battle_engine.check_hp(sender, status)

    # 전투중단/종료
    elsif command =~ /^전투중단$/i || command =~ /^전투종료$/i
      @battle_engine.stop_battle(sender, status)

    else
      puts "[파서] 알 수 없는 명령어: #{command}"
    end

  rescue => e
    puts "[파서 오류] #{e.message}"
    puts e.backtrace
  end

  private

  # @제거 + user@domain -> user + 공백 제거 + 소문자
  def normalize_id(raw)
    return nil if raw.nil?
    s = raw.to_s.strip
    s = s.sub(/\A@/, '')
    s = s.split('@', 2)[0]     # "user@domain" -> "user"
    s = s.gsub(/\s+/, '')
    s.downcase
  end

  def extract_bracket_content(text)
    match = text.match(/\[([^\]]+)\]/)
    match ? match[1] : nil
  end
end
