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
    when /\[체력\]/i
      @hp_command.check_hp(user_id, reply_status)

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

    # 제3자가 두 사람의 전투 시작 (먼저 체크해야 함)
    when /\[전투개시\/@?(\S+)\/@?(\S+)\]/i
      user1 = Regexp.last_match(1)
      user2 = Regexp.last_match(2)
      
      # 두 사용자가 모두 등록되어 있는지 확인
      player1 = @sheet_manager.find_user(user1)
      player2 = @sheet_manager.find_user(user2)
      
      unless player1 && player2
        missing = []
        missing << user1 unless player1
        missing << user2 unless player2
        @mastodon_client.reply(reply_status, "@#{user_id} 등록되지 않은 사용자: #{missing.join(', ')}")
      else
        @battle_command.handle_command(user_id, "[전투 #{user1} vs #{user2}]", reply_status)
      end

    when /\[전투개시\/@?(\S+)\]/i
      target = Regexp.last_match(1)
      @battle_command.handle_command(user_id, "[전투 #{user_id} vs #{target}]", reply_status)

    when /\[다인전투((?:\/@?\S+)+)\]/i
      participants_text = Regexp.last_match(1)
      participants = participants_text.split('/').map(&:strip).reject(&:empty?).map { |p| p.gsub('@', '') }
      
      if participants.length == 4
        @battle_command.handle_command(user_id, "[다인전투/#{participants.join('/')}]", reply_status)
      else
        @mastodon_client.reply(reply_status, "@#{user_id} 다인전투는 정확히 4명이 필요합니다. (현재: #{participants.length}명)")
      end

    when /\[허수아비\s*(하|중|상)\]/i
      diff = Regexp.last_match(1)
      @battle_command.handle_command(user_id, "[허수아비 #{diff}]", reply_status)

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

    when /\[물약사용\/(\S+)\/@?(\S+)\]/i
      potion_type = Regexp.last_match(1)
      target = Regexp.last_match(2)
      @potion_command.use_potion_for_target(user_id, reply_status, potion_type, target)

    when /\[물약사용\/@?(\S+)\]/i
      target = Regexp.last_match(1)
      @potion_command.use_potion_for_target(user_id, reply_status, nil, target)

    when /\[물약사용\/(\S+)\]/i
      potion_type = Regexp.last_match(1)
      @potion_command.use_potion(user_id, reply_status, potion_type)

    when /\[물약사용\]/i
      @potion_command.use_potion(user_id, reply_status)

    when /\[전투\s*중단\]/i, /\[전투중단\]/i
      require_relative 'core/battle_state'
      if BattleState.get && !BattleState.get.empty?
        @mastodon_client.reply(reply_status, "전투가 중단되었습니다.")
        BattleState.clear
      else
        @mastodon_client.reply(reply_status, "진행 중인 전투가 없습니다.")
      end

    when /\[조사시작\]/i,
         /\[조사\/.+\]/i,
         /\[세부조사\/.+\]/i,
         /\[이동\/.+\]/i,
         /\[위치확인\]/i,
         /\[협력조사\/.+\/@.+\]/i,
         /\[방해\/@.+\]/i,
         /\[조사종료\]/i
      @investigate_command.execute(clean_text, user_id, reply_status)

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
