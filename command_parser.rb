require_relative 'commands/battle_command'
require_relative 'commands/investigate_command'
require_relative 'commands/potion_command'
require_relative 'commands/heal_command'
require_relative 'commands/dm_investigation_command'
require_relative 'commands/hp_command'
require_relative 'commands/dungeon_command'

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
    @dungeon_command = DungeonCommand.new(mastodon_client, sheet_manager)
  end

  def handle(status)
    content = status[:content]
    text = content.gsub(/<[^>]+>/, '').strip

    user_id = status[:account][:acct]

    parse(text, user_id, status)
  end

  def parse(text, user_id, reply_status)
    text = text.strip

    # 명령어 대괄호 안의 내용은 보존하면서 외부의 봇 멘션만 제거
    # 1. 명령어 부분 임시 저장
    commands = []
    temp_text = text.gsub(/\[([^\]]+)\]/) do |match|
      commands << match
      "__CMD#{commands.length - 1}__"
    end

    # 2. 외부 멘션만 제거
    temp_text = temp_text.gsub(/@\S+\s*/, '').strip

    # 3. 명령어 복원
    commands.each_with_index do |cmd, idx|
      temp_text = temp_text.sub("__CMD#{idx}__", cmd)
    end

    clean_text = temp_text

    puts "[전투봇] 명령 수신: #{clean_text} (from @#{user_id})"

    case clean_text
    # ============================
    # 공동목표 및 레이드
    # ============================
    when /\[공동목표\/(B[2-5])\/((?:@\S+\/)*@\S+)\]/i,
         /\[레이드\/(B[2-5])\/((?:@\S+\/)*@\S+)\]/i,
         /\[맵보기\]/i,
         /\[목표상태\]/i,
         /\[이동\/(상|하|좌|우|좌상|우상|좌하|우하)\]/i,
         /\[목표공격\]/i,
         /\[목표포기\]/i
      @dungeon_command.handle_command(user_id, clean_text, reply_status)

    # ============================
    # HP 확인
    # ============================
    when /\[체력\]/i
      @hp_command.check_hp(user_id, reply_status)

    # ============================
    # 회복 명령어
    # ============================
    when /\[회복\/(\S+)\/@?(\S+)\]/i, /\[힐\/(\S+)\/@?(\S+)\]/i
      potion_type = Regexp.last_match(1)
      target = Regexp.last_match(2)
      @heal_command.use_potion_for_target(user_id, reply_status, potion_type, target)

    when /\[회복\/@?(\S+)\]/i, /\[힐\/@?(\S+)\]/i
      target = Regexp.last_match(1)
      @heal_command.use_potion_for_target(user_id, reply_status, nil, target)

    when /\[회복\/(\S+)\]/i, /\[힐\/(\S+)\]/i
      potion_type = Regexp.last_match(1)
      @heal_command.use_potion(user_id, reply_status, potion_type)

    when /\[회복\]/i, /\[힐\]/i
      @heal_command.use_potion(user_id, reply_status)

    # ============================
    # 전투 개시
    # ============================
    when /\[전투개시\/@([^@\/\]]+)\/@([^@\/\]]+)\]/i
      # 2명 지정: [전투개시/@A/@B]
      user1 = Regexp.last_match(1).strip
      user2 = Regexp.last_match(2).strip
      @battle_command.handle_command(user_id, "[전투 #{user1} vs #{user2}]", reply_status)

    when /\[전투개시\/@([^@\/\]]+)\]/i
      # 1명 지정: [전투개시/@A] → 명령자 vs A
      target = Regexp.last_match(1).strip
      @battle_command.handle_command(user_id, "[전투 #{user_id} vs #{target}]", reply_status)

    # ============================
    # 다인전투
    # ============================
    when /\[다인전투((?:\/@?\S+)+)\]/i
      participants_text = Regexp.last_match(1)
      participants = participants_text.split('/').map(&:strip).reject(&:empty?).map { |p| p.gsub('@', '') }

      if participants.length == 4
        @battle_command.handle_command(user_id, "[다인전투/#{participants.join('/')}]", reply_status)
      else
        @mastodon_client.reply(reply_status, "@#{user_id} 다인전투는 정확히 4명이 필요합니다. (현재: #{participants.length}명)")
      end

    # ============================
    # 허수아비
    # ============================
    when /\[허수아비\s*(하|중|상)\]/i
      diff = Regexp.last_match(1)
      @battle_command.handle_command(user_id, "[허수아비 #{diff}]", reply_status)

    # ============================
    # 전투 액션
    # ============================
    when /\[공격\/@?(\S+)\]/i
      target = Regexp.last_match(1)
      @battle_command.handle_command(user_id, "[공격/#{target}]", reply_status)

    when /\[공격\]/i
      @battle_command.handle_command(user_id, "[공격]", reply_status)

    when /\[방어\/@?(\S+)\]/i
      target = Regexp.last_match(1)
      @battle_command.handle_command(user_id, "[방어/#{target}]", reply_status)

    when /\[방어\]/i
      @battle_command.handle_command(user_id, "[방어]", reply_status)

    when /\[반격\]/i
      @battle_command.handle_command(user_id, "[반격]", reply_status)

    when /\[도주\]/i
      @battle_command.handle_command(user_id, "[도주]", reply_status)

    # ============================
    # 물약 명령어 (간소화된 형식)
    # ============================
    when /\[물약\/(\S+)\/@(\S+)\]/i
      # [물약/소형/@Test] - 대상에게 물약 사용
      potion_type = Regexp.last_match(1)
      target = Regexp.last_match(2)
      @potion_command.use_potion_for_target(user_id, reply_status, potion_type, target)

    when /\[물약\/@(\S+)\]/i
      # [물약/@Test] - 대상에게 물약 사용 (종류 선택)
      target = Regexp.last_match(1)
      @potion_command.use_potion_for_target(user_id, reply_status, nil, target)

    when /\[물약\/(\S+)\]/i
      # [물약/소형] - 자신에게 물약 사용
      potion_type = Regexp.last_match(1)
      @potion_command.use_potion(user_id, reply_status, potion_type)

    when /\[물약사용\]/i, /\[물약\]/i
      # [물약사용] 또는 [물약] - 목록 표시
      @potion_command.use_potion(user_id, reply_status)

    # ============================
    # 전투 중단
    # ============================
    when /\[전투\s*중단\]/i, /\[전투중단\]/i
      require_relative 'core/battle_state'
      battle_id = BattleState.find_battle_id_by_user(user_id)
      if battle_id
        @mastodon_client.reply(reply_status, "전투가 중단되었습니다.")
        BattleState.clear(battle_id)
      else
        @mastodon_client.reply(reply_status, "진행 중인 전투가 없습니다.")
      end

    # ============================
    # 조사 시스템
    # ============================
    when /\[조사시작\]/i,
         /\[조사\/.+\]/i,
         /\[세부조사\/.+\]/i,
         /\[이동\/.+\]/i,
         /\[위치확인\]/i,
         /\[협력조사\/.+\/@.+\]/i,
         /\[방해\/@.+\]/i,
         /\[조사종료\]/i
      @investigate_command.execute(clean_text, user_id, reply_status)

    # ============================
    # DM 조사 결과
    # ============================
    when /DM조사결과\s+@(\S+)\s+(.+)/i
      @dm_investigation_command.send_result(clean_text, user_id, reply_status)

    else
      puts "[무시] 인식되지 않은 명령: #{clean_text}"
    end

  rescue => e
    puts "[에러] CommandParser 오류: #{e.message}"
    puts e.backtrace.first(5)
    @mastodon_client.reply(reply_status, "명령 처리 중 오류가 발생했습니다.")
  end

  private

  def handle_location_overview(location, user_id, reply_status)
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
