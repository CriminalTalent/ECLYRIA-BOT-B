# command_parser.rb
require 'cgi'

class CommandParser
  def initialize(mastodon_client, battle_engine)
    @mastodon = mastodon_client
    @engine = battle_engine
  end

  # status: Mastodon streaming status Hash
  def parse(status)
    return unless status.is_a?(Hash)

    raw_html = status[:content].to_s
    plain = strip_html(raw_html)

    # 대괄호 명령만 처리
    bracket = extract_bracket_command(plain)
    return unless bracket

    cmd, params = split_command(bracket)

    puts "[파서] 원본 HTML: #{raw_html[0, 120]}"
    puts "[파서] HTML 제거: #{plain[0, 120]}"
    puts "[파서] 대괄호 내용: #{bracket}"
    puts "[파서] 명령어: #{cmd}"
    puts "[파서] 파라미터: #{params.inspect}"

    # visibility 규칙
    vis = status[:visibility].to_s.strip
    vis = 'public' if vis.empty?
    # DM이면 무조건 direct로 답한다
    reply_vis = (vis == 'direct') ? 'direct' : vis

    case cmd
    when '전투개시'
      # 1:1 전용
      if params.length != 2
        respond(status,
                "⚠️ [전투개시]는 1:1 전용입니다.\n" \
                "다인전투는 이렇게 써줘: [다인전투/플레이어1/플레이어2/플레이어3/플레이어4...]\n" \
                "※ @는 붙여도 되고 안 붙여도 돼요(자동 제거).",
                nil,
                reply_vis)
        return
      end

      participants = params.map { |p| normalize_user(p) }.reject(&:empty?)
      if participants.length != 2
        respond(status, "⚠️ 참가자 ID 파싱에 실패했어. 예: [전투개시/misen/Ocellio]", nil, reply_vis)
        return
      end

      start_battle(status, participants, mode: :onevone, reply_vis: reply_vis)

    when '다인전투'
      # 다인전투(2:2 / 4:4 / 그 이상도 허용)
      if params.length < 3
        respond(status,
                "⚠️ [다인전투]는 최소 3명 이상 필요해.\n" \
                "예: [다인전투/misen/Ocellio/Riley_Barnes/RASXIX]\n" \
                "※ @는 붙여도 되고 안 붙여도 돼요(자동 제거).",
                nil,
                reply_vis)
        return
      end

      participants = params.map { |p| normalize_user(p) }.reject(&:empty?).uniq
      if participants.length < 3
        respond(status, "⚠️ 참가자 ID 파싱에 실패했어. 예: [다인전투/A/B/C/D]", nil, reply_vis)
        return
      end

      start_battle(status, participants, mode: :multi, reply_vis: reply_vis)

    when '도움말'
      respond(status, help_text, nil, reply_vis)

    else
      # 모르는 명령은 조용히 스킵하거나 안내
      respond(status,
              "⚠️ 알 수 없는 명령어: #{cmd}\n" \
              "가능: [전투개시/A/B], [다인전투/A/B/C/D...], [도움말]",
              nil,
              reply_vis)
    end
  rescue => e
    puts "[파서 오류] #{e.class}: #{e.message}"
    puts e.backtrace.first(8)
  end

  private

  # -----------------------------
  # 전투 시작 호출 (엔진 메서드 호환)
  # -----------------------------
  def start_battle(status, participants, mode:, reply_vis:)
    thread_id = status[:id]

    puts "[전투] 전투 시작 요청 thread_id=#{thread_id} participants=#{participants.inspect} mode=#{mode}"

    # ✅ 엔진 구현이 어떤 이름이든 최대한 맞춰서 호출
    result = nil

    if mode == :onevone
      if @engine.respond_to?(:start_1v1)
        result = @engine.start_1v1(thread_id, participants)
      elsif @engine.respond_to?(:start_battle)
        result = @engine.start_battle(thread_id, participants)
      elsif @engine.respond_to?(:start)
        result = @engine.start(thread_id, participants)
      else
        respond(status, "❌ BattleEngine에 시작 메서드가 없어(start_1v1/start_battle/start).", participants, reply_vis)
        return
      end
    else
      if @engine.respond_to?(:start_multi)
        result = @engine.start_multi(thread_id, participants)
      elsif @engine.respond_to?(:start_group)
        result = @engine.start_group(thread_id, participants)
      elsif @engine.respond_to?(:start_battle)
        result = @engine.start_battle(thread_id, participants)
      elsif @engine.respond_to?(:start)
        result = @engine.start(thread_id, participants)
      else
        respond(status, "❌ BattleEngine에 다인전투 시작 메서드가 없어(start_multi/start_group/start_battle/start).", participants, reply_vis)
        return
      end
    end

    # 엔진이 메시지를 반환하면 출력해주고, 아니면 기본 성공 메시지
    msg =
      if result.is_a?(String) && !result.strip.empty?
        result
      else
        if mode == :onevone
          "✅ 1:1 전투가 개설되었습니다.\n참가: #{participants.join(' vs ')}"
        else
          "✅ 다인전투가 개설되었습니다.\n참가: #{participants.map { |u| "@#{u}" }.join(' ')}"
        end
      end

    respond(status, msg, participants, reply_vis)
  end

  # -----------------------------
  # 응답 규칙
  # - DM으로 왔으면 direct로 (참가자 태그 포함하면 DM 공유됨)
  # - public/unlisted/private면 항상 참가자 전원 태그해서 reply
  # -----------------------------
  def respond(status, message, participants, reply_vis)
    if reply_vis == 'direct'
      # direct는 멘션된 사람만 보이므로 참가자 태그를 넣어주는 게 맞음
      if participants && participants.any?
        @mastodon.reply_with_mentions(status, message, participants, visibility: 'direct')
      else
        @mastodon.reply(status, message, visibility: 'direct')
      end
    else
      if participants && participants.any?
        @mastodon.reply_with_mentions(status, message, participants, visibility: reply_vis)
      else
        @mastodon.reply(status, message, visibility: reply_vis)
      end
    end
  rescue => e
    puts "[응답 오류] #{e.class}: #{e.message}"
  end

  # -----------------------------
  # 텍스트 처리
  # -----------------------------
  def strip_html(html)
    s = html.to_s.dup
    s = CGI.unescapeHTML(s)
    # 태그 제거
    s = s.gsub(/<[^>]+>/, ' ')
    # 공백 정리
    s = s.gsub(/\s+/, ' ').strip
    s
  end

  def extract_bracket_command(text)
    m = text.match(/\[([^\]]+)\]/m)
    return nil unless m
    m[1].to_s.strip
  end

  def split_command(bracket_content)
    parts = bracket_content.split('/').map { |x| x.to_s.strip }.reject(&:empty?)
    cmd = parts.shift.to_s
    params = parts
    # @ 제거/정규화는 나중에 normalize_user에서 처리
    [cmd, params]
  end

  def normalize_user(raw)
    s = raw.to_s.strip
    s = s.sub(/\A@/, '')
    s = s.split('@', 2)[0] # user@domain -> user
    s = s.gsub(/\s+/, '')
    s.downcase
  end

  def help_text
    <<~TXT.strip
    ✅ 전투 명령어

    1) 1:1 전투
    [전투개시/플레이어1/플레이어2]
    예: [전투개시/misen/Ocellio]
    예: [전투개시/@misen/@Ocellio]  (※ @ 자동 제거)

    2) 다인전투 (2:2 / 4:4 / 그 이상 가능)
    [다인전투/플레이어1/플레이어2/플레이어3/플레이어4...]
    예: [다인전투/misen/Ocellio/Riley_Barnes/RASXIX]

    3) 도움말
    [도움말]

    📌 DM으로 시작하면 답도 전부 DM(Direct)으로 나가고,
    퍼블릭으로 시작하면 항상 참가자 전원 태그해서 퍼블릭으로 답합니다.
    TXT
  end
end
