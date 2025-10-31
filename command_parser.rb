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
    
    if text.match(/\[전투개시[/@]/i)
      @battle_command.start_battle(text, user_id, reply_id)
    elsif text.match(/\[허수아비\s+(상|중|하)\]/i)
      @battle_command.start_dummy_battle(text, user_id, reply_id)
    elsif text.match(/\[(공격|방어|반격|도주)\]/i)
      @battle_command.handle_action(text, user_id, reply_id)
    elsif text.match(/\[물약사용\]/i)
      @potion_command.use_potion(user_id, reply_id)
    elsif text.match(/DM조사결과\s+@(\S+)\s+(.+)/i)
      @dm_investigation_command.send_result(text, user_id, reply_id)
    elsif text.match(/\[(조사|정밀조사|감지|훔쳐보기)\]\s*(.+)/i)
      @investigate_command.investigate(text, user_id, reply_id)
    else
      @mastodon_client.reply(reply_id, "알 수 없는 명령어입니다.", visibility: 'direct')
    end
  rescue => e
    puts "Parse error: #{e.message}"
    puts e.backtrace.join("\n")
    @mastodon_client.reply(reply_id, "명령 처리 중 오류가 발생했습니다.", visibility: 'direct')
  end
end
