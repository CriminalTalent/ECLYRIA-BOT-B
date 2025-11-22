require_relative 'commands/battle_command'
require_relative 'commands/investigate_command'
require_relative 'commands/potion_command'
require_relative 'commands/heal_command'
require_relative 'commands/dm_investigation_command'
require_relative 'commands/hp_command'

class CommandParser
  def initialize(mastodon_client, sheet_manager)
    @mastodon_client = mastodon_client
    @sheet_manager = sheet_manager

    @battle_command = BattleCommand.new(mastodon_client, sheet_manager)
    @investigate_command = InvestigateCommand.new(mastodon_client, sheet_manager)
    @potion_command = PotionCommand.new(mastodon_client, sheet_manager)
    @heal_command = HealCommand.new(mastodon_client, sheet_manager)
    @dm_investigation_command = DMInvestigationCommand.new(mastodon_client, sheet_manager)
    @hp_command = HpCommand.new(mastodon_client, sheet_manager)
  end

  # 해시 형태의 status를 받아서 처리
  def handle(status)
    # HTML 태그 제거 및 텍스트 추출
    content = status[:content]
    text = content.gsub(/<[^>]+>/, '').strip

    user_id = status[:account][:acct]

    # status 자체를 reply_status로 전달 (해시 형태)
    parse(text, user_id, status)
  end

  def parse(text, user_id, reply_status)
    text = text.strip
    puts "[전투봇] 명령 수신: #{text} (from @#{user_id})"

    case text
    # === 체력 확인 ===
    when /\[체력\]/i
      @hp_command.check_hp(user_id, reply_status)

    # === 물약 사용 (전투 외) ===
    when /\[회복\]/i, /\[힐\]/i
      @heal_command.use_potion(user_id, reply_status)

    # === 전투 관련 ===
    when /\[전투개시\/@?(\S+)\]/i
      target = Regexp.last_match(1)
      @battle_command.handle_command(user_id, "[전투 #{user_id} vs #{target}]", reply_status)

    when /\[전투개시\/@?(\S+)\/@?(\S+)\/@?(\S+)\/@?(\S+)\]/i
      u1, u2, u3, u4 = Regexp.last_match.captures
      @battle_command.handle_command(user_id, "[전투 #{u1} #{u2} vs #{u3} #{u4}]", reply_status)

    when /\[허수아비\s*(하|중|상)\]/i
      diff = Regexp.last_match(1)
      @battle_command.handle_command(user_id, "[허수아비 #{diff}]", reply_status)

    when /\[(공격|방어|반격|도주)\]/i
      action = Regexp.last_match(1)
      @battle_command.handle_command(user_id, "[#{action}]", reply_status)

    when /\[물약사용\]/i
      @potion_command.use_potion(user_id, reply_status)

    when /\[전투중단\]/i
      @mastodon_client.reply(reply_status, "전투가 총괄에 의해 중단되었습니다.")
      require_relative 'core/battle_state'
      BattleState.clear

    # === 조사 관련 ===
    when /\[조사시작\]/i,
         /\[조사\/.+\]/i,
         /\[세부조사\/.+\]/i,
         /\[이동\/.+\]/i,
         /\[위치확인\]/i,
         /\[협력조사\/.+\/@.+\]/i,
         /\[방해\/@.+\]/i,
         /\[조사종료\]/i
      @investigate_command.execute(text, user_id, reply_status)

    # === DM 조사결과 전송 ===
    when /DM조사결과\s+@(\S+)\s+(.+)/i
      @dm_investigation_command.send_result(text, user_id, reply_status)

    else
      puts "[무시] 인식되지 않은 명령: #{text}"
      # 명령어가 없으면 무시 (대사만 있는 경우)
    end

  rescue => e
    puts "[에러] CommandParser 오류: #{e.message}"
    puts e.backtrace.first(5)
    @mastodon_client.reply(reply_status, "명령 처리 중 오류가 발생했습니다.")
  end

  private

  def handle_location_overview(location, user_id, reply_status)
    # 조사상태 시트에 위치 반영 (없으면 추가, 있으면 갱신)
    @sheet_manager.upsert_investigation_state(user_id, "조사중", location)

    unless @sheet_manager.is_location?(location)
      locations = @sheet_manager.available_locations || []

      msg_lines = []
      msg_lines << "@#{user_id}"
      msg_lines << "'#{location}'(은)는 아직 조사할 수 없는 위치야."

      unless locations.empty?
        msg_lines << ""
        msg_lines << "지금 조사할 수 있는 위치는 다음과 같아:"
        locations.each { |loc| msg_lines << "- #{loc}" }
      end

      @mastodon_client.reply(reply_status, msg_lines.join("\n"))
      return
    end

    overviews = @sheet_manager.location_overview_outputs(location) || []
    details   = @sheet_manager.detail_candidates(location)       || []

    lines = []
    lines << "@#{user_id}"
    lines << "#{location}을(를) 둘러본다."
    lines << ""

    if overviews.any?
      lines << overviews.join("\n\n")
    else
      lines << "아직 이 위치에 대한 설명이 준비되지 않았어."
    end

    if details.any?
      lines << ""
      lines << "[세부 조사 가능 구역]"
      details.each { |d| lines << "- #{d}" }
    end

    @mastodon_client.reply(reply_status, lines.join("\n"))
  end
end
