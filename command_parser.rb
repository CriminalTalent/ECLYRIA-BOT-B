require_relative 'commands/battle_command'
require_relative 'commands/investigate_command'
require_relative 'commands/potion_command'
require_relative 'commands/dm_investigation_command'

class CommandParser
  def initialize(mastodon_client, sheet_manager)
    @mastodon_client = mastodon_client
    @sheet_manager = sheet_manager

    @battle_command = BattleCommand.new(mastodon_client, sheet_manager)
    @investigate_command = InvestigateCommand.new(mastodon_client, sheet_manager)
    @potion_command = PotionCommand.new(mastodon_client, sheet_manager)
    @dm_investigation_command = DMInvestigationCommand.new(mastodon_client, sheet_manager)
  end

  def parse(text, user_id, reply_id)
    text = text.strip
    puts "[전투봇] 명령 수신: #{text} (from @#{user_id})"

    case text
    # === 전투 관련 ===
    when /\[전투개시\/@?(\S+)\]/i
      target = Regexp.last_match(1)
      @battle_command.handle_command(user_id, "[전투 #{user_id} vs #{target}]", reply_id)

    when /\[전투개시\/@?(\S+)\/@?(\S+)\/@?(\S+)\/@?(\S+)\]/i
      u1, u2, u3, u4 = Regexp.last_match.captures
      @battle_command.handle_command(user_id, "[전투 #{u1} #{u2} vs #{u3} #{u4}]", reply_id)

    when /\[허수아비\s*(하|중|상)\]/i
      diff = Regexp.last_match(1)
      @battle_command.handle_command(user_id, "[허수아비 #{diff}]", reply_id)

    when /\[(공격|방어|반격|도주)\]/i
      @battle_command.handle_command(user_id, text, reply_id)

    when /\[물약사용\]/i
      @potion_command.use_potion(user_id, reply_id)

    when /\[전투중단\]/i
      @mastodon_client.reply(reply_id, "전투가 총괄에 의해 중단되었습니다.", visibility: 'public')
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
      @investigate_command.execute(text, user_id, reply_id)

    # === DM 조사결과 전송 ===
    when /DM조사결과\s+@(\S+)\s+(.+)/i
      @dm_investigation_command.send_result(text, user_id, reply_id)

    else
      puts "[무시] 인식되지 않은 명령: #{text}"
      @mastodon_client.reply(reply_id, "알 수 없는 명령어입니다.", visibility: 'direct')
    end

  rescue => e
    puts "[에러] CommandParser 오류: #{e.message}"
    puts e.backtrace.first(5)
    @mastodon_client.reply(reply_id, "명령 처리 중 오류가 발생했습니다.", visibility: 'direct')
  end
end
