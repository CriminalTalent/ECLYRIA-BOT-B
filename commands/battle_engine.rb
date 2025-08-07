# core/battle_engine.rb

require_relative './sheet_manager'
require_relative './battle_state'

module BattleEngine
  module_function

  def init_1v1(players, sheet)
    BattleState.set(players: players, turn: nil, sheet: sheet)
  end

  def init_team_battle(team_a, team_b, sheet)
    BattleState.set(players: team_a + team_b, team_a: team_a, team_b: team_b, turn: nil, sheet: sheet)
  end

  def roll_initiative(players)
    stats = players.map { |p| [p, SheetManager.get_stat(p, "민첩") + rand(1..20)] }
    sorted = stats.sort_by { |_, roll| -roll }

    BattleState.set_turn(sorted[0][0])
    msg = "자동봇 : 선공 #{sorted[0][0]}, 후공 #{sorted[1][0]} 전투를 시작합니다."
    BattleState.say(msg)
  end

  def roll_team_initiative(team_a, team_b)
    a_total = team_a.sum { |p| SheetManager.get_stat(p, "민첩") } / team_a.size + rand(1..20)
    b_total = team_b.sum { |p| SheetManager.get_stat(p, "민첩") } / team_b.size + rand(1..20)

    first_team = a_total >= b_total ? team_a : team_b
    BattleState.set_turn(first_team[0]) # 팀의 첫 번째 플레이어
    msg = "자동봇 : 선공 팀 (#{first_team.join(", ")}) 전투를 시작합니다."
    BattleState.say(msg)
  end

  def attack(user)
    defender = BattleState.get_opponent(user)
    atk = SheetManager.get_stat(user, "공격력") + rand(1..20)
    def_val = SheetManager.get_stat(defender, "방어") + rand(1..20)

    dmg = [atk - def_val, 0].max
    new_hp = SheetManager.get_stat(defender, "체력") - dmg
    SheetManager.set_stat(defender, "체력", new_hp)

    msg = "#{user}의 공격! #{defender}에게 #{dmg} 피해를 입혔습니다.\n"
    msg += "자동봇 : #{user}의 공격 : #{atk}, #{defender}의 방어 : #{def_val}\n"
    msg += "남은 체력 - #{user}: #{SheetManager.get_stat(user, '체력')} / #{defender}: #{new_hp}"

    BattleState.say(msg)

    check_ending(defender)
    BattleState.next_turn
  end

  def defend(user)
    msg = "#{user}이(가) 방어 자세를 취합니다. 다음 턴으로 넘어갑니다."
    BattleState.say(msg)
    BattleState.next_turn
  end

  def counter(user)
    attacker = BattleState.get_opponent(user)
    counter = SheetManager.get_stat(user, "공격력") + rand(1..20)
    def_val = SheetManager.get_stat(attacker, "방어") + rand(1..20)

    dmg = [counter - def_val, 0].max
    new_hp = SheetManager.get_stat(attacker, "체력") - dmg
    SheetManager.set_stat(attacker, "체력", new_hp)

    msg = "#{user}의 반격! #{attacker}에게 #{dmg} 피해를 입혔습니다.\n"
    msg += "자동봇 : #{user}의 반격 : #{counter}, #{attacker}의 방어 : #{def_val}\n"
    msg += "남은 체력 - #{attacker}: #{new_hp} / #{user}: #{SheetManager.get_stat(user, '체력')}"

    BattleState.say(msg)

    check_ending(attacker)
    BattleState.next_turn
  end

  def escape(user)
    opp = BattleState.get_opponent(user)
    luck = SheetManager.get_stat(user, "행운")
    agi = SheetManager.get_stat(user, "민첩")
    esc_val = luck + agi + rand(1..20)
    block_val = SheetManager.get_stat(opp, "민첩") + rand(1..20)

    if esc_val > block_val
      msg = "#{user}의 도주 성공! 전투를 종료합니다."
      BattleState.say(msg)
      BattleState.end
    else
      msg = "#{user}의 도주 실패! 전투는 계속됩니다."
      BattleState.say(msg)
      BattleState.next_turn
    end
  end

  def use_potion(user)
    amount = [5, 10, 15, 20].sample
    cur_hp = SheetManager.get_stat(user, "체력")
    SheetManager.set_stat(user, "체력", cur_hp + amount)
    msg = "#{user}의 체력이 #{amount} 회복되었습니다. 현재 체력: #{cur_hp + amount}"
    BattleState.say(msg)
    BattleState.next_turn
  end

  def check_ending(player)
    if SheetManager.get_stat(player, "체력") <= 0
      msg = "#{player}의 체력이 0이 되어 전투가 종료됩니다."
      BattleState.say(msg)
      BattleState.end
    end
  end
end

