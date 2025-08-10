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
    when /^전투개시\s+@?(\w+)/
      opponent = $1
      start_battle(sender, opponent, in_reply_to_id)
    when /^DM전투개시\s+(.+)vs(.+)/
      team_a = $1.strip.split(/\s+/)
      team_b = $2.strip.split(/\s+/)
      start_dm_battle(team_a, team_b, in_reply_to_id)
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

  def start_battle(user_id, opponent_id, reply_id)
    if BattleState.in_battle?(user_id) || BattleState.in_battle?(opponent_id)
      @mastodon_client.reply(user_id, "당신 혹은 #{opponent_id}는 이미 전투 중입니다.", in_reply_to_id: reply_id)
      return
    end

    players = [user_id, opponent_id]
    BattleEngine.init_1v1(players)
    BattleEngine.roll_initiative(players)
  end

  def start_dm_battle(team_a, team_b, reply_id)
    players = team_a + team_b
    if players.any? { |p| BattleState.in_battle?(p) }
      @mastodon_client.say("참가자 중 이미 전투 중인 유저가 있습니다.")
      return
    end

    BattleEngine.init_team_battle(team_a, team_b)
    BattleEngine.roll_team_initiative(team_a, team_b)
  end
end
