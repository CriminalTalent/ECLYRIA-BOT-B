# commands/battle_command.rb
require_relative '../core/battle_engine'
require_relative '../core/battle_state'

class BattleCommand
  def initialize(mastodon_client, sheet_manager)
    @mastodon_client = mastodon_client
    @sheet_manager = sheet_manager
    
    BattleState.set_mastodon_client(@mastodon_client)
    BattleEngine.set_sheet_manager(@sheet_manager)
  end

  def handle(status)
    content = status.content.gsub(/<[^>]+>/, '').strip
    sender_full = status.account.acct
    sender = sender_full.split('@').first
    display_name = status.account.display_name || sender
    in_reply_to_id = status.id
    
    # DM인지 타임라인인지 확인
    context = status.visibility == 'direct' ? 'dm' : 'timeline'

    case content
    when /\[전투개시\/@?(\w+)\/@?(\w+)\/@?(\w+)\]/
      teammate = $1
      opponent1 = $2  
      opponent2 = $3
      start_team_battle(sender, teammate, opponent1, opponent2, in_reply_to_id, context)
    when /\[전투개시\/@?(\w+)\]/
      opponent = $1
      start_1v1_battle(sender, opponent, in_reply_to_id, context)
    when /\[허수아비\s+(상|중|하)\]/
      difficulty = $1
      start_scarecrow_battle(sender, difficulty, in_reply_to_id, context)
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

  def start_1v1_battle(user_id, opponent_id, reply_id, context)
    if BattleState.in_battle?(user_id) || BattleState.in_battle?(opponent_id)
      reply_method = context == 'dm' ? :dm : :reply
      @mastodon_client.send(reply_method, user_id, "당신 혹은 #{opponent_id}는 이미 전투 중입니다.", in_reply_to_id: reply_id)
      return
    end

    players = [user_id, opponent_id]
    BattleEngine.init_1v1(players, context)
    BattleEngine.roll_initiative(players)
  end

  def start_team_battle(user_id, teammate, opponent1, opponent2, reply_id, context)
    team_a = [user_id, teammate]
    team_b = [opponent1, opponent2]
    all_players = team_a + team_b
    
    if all_players.any? { |p| BattleState.in_battle?(p) }
      reply_method = context == 'dm' ? :dm : :reply
      @mastodon_client.send(reply_method, user_id, "참가자 중 이미 전투 중인 유저가 있습니다.", in_reply_to_id: reply_id)
      return
    end

    BattleEngine.init_team_battle(team_a, team_b, context)
    BattleEngine.roll_team_initiative(team_a, team_b)
  end

  def start_scarecrow_battle(user_id, difficulty, reply_id, context)
    if BattleState.in_battle?(user_id)
      reply_method = context == 'dm' ? :dm : :reply
      @mastodon_client.send(reply_method, user_id, "이미 전투 중입니다.", in_reply_to_id: reply_id)
      return
    end

    scarecrow_id = "허수아비_#{difficulty}"
    players = [user_id, scarecrow_id]
    BattleEngine.init_scarecrow_battle(players, difficulty, context)
    BattleEngine.roll_initiative(players)
  end
end
