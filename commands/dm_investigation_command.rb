# commands/battle_command.rb
require_relative '../core/battle_engine'
require_relative '../core/battle_state'

class BattleCommand
  def initialize(mastodon_client, sheet_manager)
    @mastodon_client = mastodon_client
    @sheet_manager = sheet_manager
    
    # BattleEngine과 BattleState에 클라이언트 전달
    BattleState.set_mastodon_client(@mastodon_client)
    BattleEngine.set_sheet_manager(@sheet_manager)
  end

  def handle(status)
    content = status.content.gsub(/<[^>]+>/, '').strip
    sender_full = status.account.acct
    sender = sender_full.split('@').first
    display_name = status.account.display_name || sender
    in_reply_to_id = status.id

    case content
    when /\[전투개시\/@?(\w+)\/@?(\w+)\/@?(\w+)\]/
      teammate = $1
      opponent1 = $2  
      opponent2 = $3
      start_team_battle(sender, teammate, opponent1, opponent2, in_reply_to_id)
    when /\[허수아비\s+(상|중|하)\]/
      difficulty = $1
      start_scarecrow_battle(sender, difficulty, in_reply_to_id)
    when /공격/
      BattleEngine.attack(sender)
    when /방어/
      BattleEngine.defend(sender)
    when /반격/
      BattleEngine.counter(sender)
    when /도주/
      BattleEngine.escape(sender)
    when /물약사용/
      BattleEngine.use_potion(sender)
    else
      return
    end
  end

  private

  def start_team_battle(user_id, teammate, opponent1, opponent2, reply_id)
    team_a = [user_id, teammate]
    team_b = [opponent1, opponent2]
    all_players = team_a + team_b
    
    if all_players.any? { |p| BattleState.in_battle?(p) }
      @mastodon_client.reply(user_id, "참가자 중 이미 전투 중인 유저가 있습니다.", in_reply_to_id: reply_id)
      return
    end

    BattleEngine.init_team_battle(team_a, team_b)
    BattleEngine.roll_team_initiative(team_a, team_b)
  end

  def start_scarecrow_battle(user_id, difficulty, reply_id)
    if BattleState.in_battle?(user_id)
      @mastodon_client.reply(user_id, "이미 전투 중입니다.", in_reply_to_id: reply_id)
      return
    end

    scarecrow_id = "허수아비_#{difficulty}"
    players = [user_id, scarecrow_id]
    BattleEngine.init_scarecrow_battle(players, difficulty)
    BattleEngine.roll_initiative(players)
  end
end
