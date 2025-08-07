# commands/battle_command.rb

require_relative '../core/battle_engine'
require_relative '../core/sheet_manager'
require_relative '../core/battle_state'

class BattleCommand
  def initialize(masto, sheet)
    @masto = masto
    @sheet = sheet
  end

  def handle(status)
    content = status[:content]
    user_id = status[:account][:acct]
    display_name = status[:account][:display_name] || user_id
    in_reply_to_id = status[:id]

    case content
    when /^전투개시\s+@(\w+)/
      opponent = "@#{$1}"
      start_battle(user_id, opponent, in_reply_to_id)

    when /^DM전투개시\s+(.+)vs(.+)/
      team_a = $1.strip.split(/\s+/)
      team_b = $2.strip.split(/\s+/)
      start_dm_battle(team_a, team_b, in_reply_to_id)

    when /공격/
      BattleEngine.attack(user_id)

    when /방어/
      BattleEngine.defend(user_id)

    when /반격/
      BattleEngine.counter(user_id)

    when /도주/
      BattleEngine.escape(user_id)

    when /물약사용/
      BattleEngine.use_potion(user_id)

    else
      return
    end
  end

  private

  def start_battle(user_id, opponent_id, reply_id)
    if BattleState.in_battle?(user_id) || BattleState.in_battle?(opponent_id)
      @masto.reply(user_id, "당신 혹은 #{opponent_id}는 이미 전투 중입니다.", in_reply_to_id: reply_id)
      return
    end

    players = [user_id, opponent_id]
    BattleEngine.init_1v1(players, @sheet)
    BattleEngine.roll_initiative(players)
  end

  def start_dm_battle(team_a, team_b, reply_id)
    players = team_a + team_b
    if players.any? { |p| BattleState.in_battle?(p) }
      @masto.say("참가자 중 이미 전투 중인 유저가 있습니다.")
      return
    end

    BattleEngine.init_team_battle(team_a, team_b, @sheet)
    BattleEngine.roll_team_initiative(team_a, team_b)
  end
end
