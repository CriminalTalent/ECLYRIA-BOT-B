require_relative 'commands/battle_command'
require_relative 'commands/potion_command'
require_relative 'commands/heal_command'
require_relative 'commands/dm_investigation_command'
require_relative 'commands/hp_command'
require_relative 'commands/end_battle_command'

class CommandParser
  GM_ACCOUNTS = ['Story', 'professor', 'Store', 'FortunaeFons'].freeze

  def initialize(mastodon_client, sheet_manager)
    @mastodon_client = mastodon_client
    @sheet_manager = sheet_manager
    @battle_command = BattleCommand.new(mastodon_client, sheet_manager)
    @potion_command = PotionCommand.new(mastodon_client, sheet_manager)
    @heal_command = HealCommand.new(mastodon_client, sheet_manager)
    @dm_investigation_command = DMInvestigationCommand.new(mastodon_client, sheet_manager)
    @hp_command = HpCommand.new(mastodon_client, sheet_manager)
    @end_battle_command = EndBattleCommand.new(mastodon_client, sheet_manager)
    puts "[파서] 초기화 완료"
  end

  def handle(status)
    content = status[:content]
    text = content.gsub(/<[^>]+>/, '').strip
    user_id = status[:account][:acct]
    parse(text, user_id, status)
  end

  def parse(text, user_id, reply_status)
    text = text.strip
    clean_text = text.gsub(/@battle\s*/i, '').strip
    
    puts "[전투봇] 명령 수신: #{clean_text} (from @#{user_id})"

    # GM 전투 중단
    if text =~ /\[전투중단\s*\/\s*@?([^\s\/\]]+)\s*\/\s*@?([^\s\/\]]+)\s*\]/i
      if GM_ACCOUNTS.include?(user_id)
        player1 = $1.strip
        player2 = $2.strip
        @end_battle_command.handle(reply_status, user_id, player1, player2)
      else
        @mastodon_client.reply(reply_status, "GM 권한이 필요합니다.")
      end
      return
    end

    case clean_text
    when /\[체력\]/i
      @hp_command.check_hp(user_id, reply_status)

    # [전투개시/@A/@B] - GM이 A vs B 전투 시작
    # [전투개시/@A] - 명령자 vs A 전투
    when /\[(전투개시)\/(.+?)\]/i
      body = $2.to_s.strip
      parts = body.split('/').map { |x| x.strip.gsub('@','') }.reject(&:empty?)
      if parts.length >= 2
        a, b = parts[0], parts[1]
        @battle_command.handle_command(user_id, "[전투 #{a} vs #{b}]", reply_status)
      elsif parts.length == 1
        target = parts[0]
        @battle_command.handle_command(user_id, "[전투 #{user_id} vs #{target}]", reply_status)
      else
        @mastodon_client.reply(reply_status, "전투개시 형식: [전투개시/@A] 또는 [전투개시/@A/@B]")
      end

    when /\[다인전투((?:\/@?\S+)+)\]/i
      participants_text = $1
      participants = participants_text.split('/').map(&:strip).reject(&:empty?).map { |p| p.gsub('@', '') }
      if participants.length == 4
        @battle_command.handle_command(user_id, "[다인전투/#{participants.join('/')}]", reply_status)
      else
        @mastodon_client.reply(reply_status, "다인전투는 정확히 4명이 필요합니다. (현재: #{participants.length}명)")
      end

    when /\[허수아비\s*(하|중|상)\]/i
      diff = $1
      @battle_command.handle_command(user_id, "[허수아비 #{diff}]", reply_status)

    when /\[공격\/@?(\S+)\]/i
      target = $1
      @battle_command.handle_command(user_id, "[공격/#{target}]", reply_status)

    when /\[공격\]/i
      @battle_command.handle_command(user_id, "[공격]", reply_status)

    when /\[방어\/@?(\S+)\]/i
      target = $1
      @battle_command.handle_command(user_id, "[방어/#{target}]", reply_status)

    when /\[방어\]/i
      @battle_command.handle_command(user_id, "[방어]", reply_status)

    when /\[반격\]/i
      @battle_command.handle_command(user_id, "[반격]", reply_status)

    when /\[도주\]/i
      @battle_command.handle_command(user_id, "[도주]", reply_status)

    # 탐색 명령어 (추후 구현)
    when /\[탐색시작\/([A-Z]\d+)\]/i
      location = $1
      @mastodon_client.reply(reply_status, "@#{user_id} 탐색 기능은 준비 중입니다.")

    when /\[협력탐색\/([A-Z]\d+)((?:\/@?\S+)*)\]/i
      location = $1
      participants = $2.split('/').map(&:strip).reject(&:empty?).map { |p| p.gsub('@', '') }
      @mastodon_client.reply(reply_status, "@#{user_id} 협력탐색 기능은 준비 중입니다.")

    when /\[이동\/(\S+)\]/i
      direction = $1
      @mastodon_client.reply(reply_status, "@#{user_id} 이동 기능은 준비 중입니다.")

    when /\[목표공격\]/i
      @mastodon_client.reply(reply_status, "@#{user_id} 목표공격 기능은 준비 중입니다.")

    when /\[조사시작\]/i
      @mastodon_client.reply(reply_status, "@#{user_id} 조사 기능은 준비 중입니다.")

    when /\[물약\/(\S+)\]/i
      potion_type = $1
      @potion_command.use_potion(user_id, reply_status, potion_type)

    when /\[물약사용\]/i, /\[물약\]/i
      @potion_command.use_potion(user_id, reply_status)

    when /\[전투\s*중단\]/i, /\[전투중단\]/i
      require_relative 'core/battle_state'
      battle_id = BattleState.find_battle_id_by_user(user_id)
      if battle_id
        BattleState.clear(battle_id)
        @mastodon_client.reply(reply_status, "@#{user_id} 전투를 중단했습니다.")
      else
        @mastodon_client.reply(reply_status, "@#{user_id} 현재 전투 중이 아닙니다.")
      end

    else
      puts "[무시] 인식되지 않은 명령: #{clean_text}"
    end

  rescue => e
    puts "[에러] CommandParser 오류: #{e.message}"
    puts e.backtrace.first(5)
    @mastodon_client.reply(reply_status, "@#{user_id} 명령 처리 중 오류가 발생했습니다.")
  end
end
