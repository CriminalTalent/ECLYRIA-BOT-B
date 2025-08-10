# core/battle_engine.rb
require_relative 'battle_state'

module BattleEngine
  module_function

  @@sheet_manager = nil

  def set_sheet_manager(sheet_manager)
    @@sheet_manager = sheet_manager
  end

  def init_1v1(players)
    BattleState.set(players: players, turn: nil)
  end

  def init_team_battle(team_a, team_b)
    BattleState.set(players: team_a + team_b, team_a: team_a, team_b: team_b, turn: nil)
  end

  def roll_initiative(players)
    stats = players.map do |p|
      agility = @@sheet_manager.get_stat(p, "민첩")
      agi_value = agility ? agility.to_i : 10
      [p, agi_value + rand(1..20)]
    end
    sorted = stats.sort_by { |_, roll| -roll }

    BattleState.set_turn(sorted[0][0])
    msg = "선공 #{sorted[0][0]}, 후공 #{sorted[1][0]} 전투를 시작합니다."
    BattleState.say(msg)
  end

  def roll_team_initiative(team_a, team_b)
    a_total = team_a.sum do |p|
      agility = @@sheet_manager.get_stat(p, "민첩")
      agility ? agility.to_i : 10
    end / team_a.size + rand(1..20)
    
    b_total = team_b.sum do |p|
      agility = @@sheet_manager.get_stat(p, "민첩")
      agility ? agility.to_i : 10
    end / team_b.size + rand(1..20)

    first_team = a_total >= b_total ? team_a : team_b
    BattleState.set_turn(first_team[0]) # 팀의 첫 번째 플레이어
    msg = "선공 팀 (#{first_team.join(", ")}) 전투를 시작합니다."
    BattleState.say(msg)
  end

  def attack(user)
    unless BattleState.is_current_turn?(user)
      BattleState.say("#{user}님의 턴이 아닙니다.")
      return
    end

    defender = BattleState.get_opponent(user)
    
    atk_stat = @@sheet_manager.get_stat(user, "공격력")
    def_stat = @@sheet_manager.get_stat(defender, "방어력")
    
    atk = (atk_stat ? atk_stat.to_i : 10) + rand(1..20)
    def_val = (def_stat ? def_stat.to_i : 10) + rand(1..20)

    dmg = [atk - def_val, 0].max
    
    hp_stat = @@sheet_manager.get_stat(defender, "체력")
    current_hp = hp_stat ? hp_stat.to_i : 100
    new_hp = current_hp - dmg
    
    @@sheet_manager.set_stat(defender, "체력", new_hp)

    msg = "#{user}의 공격! #{defender}에게 #{dmg} 피해를 입혔습니다.\n"
    msg += "#{user}의 공격 : #{atk}, #{defender}의 방어 #{def_val}\n"
    
    user_hp = @@sheet_manager.get_stat(user, "체력")
    user_hp_val = user_hp ? user_hp.to_i : 100
    msg += "남은 체력 - #{user}: #{user_hp_val} / #{defender}: #{new_hp}"

    BattleState.say(msg)

    check_ending(defender)
    BattleState.next_turn
  end

  def defend(user)
    unless BattleState.is_current_turn?(user)
      BattleState.say("#{user}님의 턴이 아닙니다.")
      return
    end

    msg = "#{user}이(가) 방어 자세를 취합니다. 다음 턴으로 넘어갑니다."
    BattleState.say(msg)
    BattleState.next_turn
  end

  def counter(user)
    unless BattleState.is_current_turn?(user)
      BattleState.say("#{user}님의 턴이 아닙니다.")
      return
    end

    attacker = BattleState.get_opponent(user)
    
    counter_stat = @@sheet_manager.get_stat(user, "공격력")
    def_stat = @@sheet_manager.get_stat(attacker, "방어력")
    
    counter = (counter_stat ? counter_stat.to_i : 10) + rand(1..20)
    def_val = (def_stat ? def_stat.to_i : 10) + rand(1..20)

    dmg = [counter - def_val, 0].max
    
    hp_stat = @@sheet_manager.get_stat(attacker, "체력")
    current_hp = hp_stat ? hp_stat.to_i : 100
    new_hp = current_hp - dmg
    
    @@sheet_manager.set_stat(attacker, "체력", new_hp)

    msg = "#{user}의 반격! #{attacker}에게 #{dmg} 피해를 입혔습니다.\n"
    msg += "#{user}의 반격 #{counter}, #{attacker}의 방어 #{def_val}\n"
    
    user_hp = @@sheet_manager.get_stat(user, "체력")
    user_hp_val = user_hp ? user_hp.to_i : 100
    msg += "남은 체력 - #{attacker}: #{new_hp} / #{user}: #{user_hp_val}"

    BattleState.say(msg)

    check_ending(attacker)
    BattleState.next_turn
  end

  def escape(user)
    unless BattleState.is_current_turn?(user)
      BattleState.say("#{user}님의 턴이 아닙니다.")
      return
    end

    opp = BattleState.get_opponent(user)
    
    luck_stat = @@sheet_manager.get_stat(user, "행운")
    agi_stat = @@sheet_manager.get_stat(user, "민첩")
    opp_agi_stat = @@sheet_manager.get_stat(opp, "민첩")
    
    luck = luck_stat ? luck_stat.to_i : 10
    agi = agi_stat ? agi_stat.to_i : 10
    opp_agi = opp_agi_stat ? opp_agi_stat.to_i : 10
    
    esc_val = luck + agi + rand(1..20)
    block_val = opp_agi + rand(1..20)

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
    unless BattleState.is_current_turn?(user)
      BattleState.say("#{user}님의 턴이 아닙니다.")
      return
    end

    amount = [5, 10, 15, 20].sample
    hp_stat = @@sheet_manager.get_stat(user, "체력")
    cur_hp = hp_stat ? hp_stat.to_i : 100
    new_hp = [cur_hp + amount, 100].min
    
    @@sheet_manager.set_stat(user, "체력", new_hp)
    msg = "#{user}의 체력이 #{amount} 회복되었습니다. 현재 체력 #{new_hp}"
    BattleState.say(msg)
    BattleState.next_turn
  end

  def check_ending(player)
    hp_stat = @@sheet_manager.get_stat(player, "체력")
    hp = hp_stat ? hp_stat.to_i : 100
    
    if hp <= 0
      msg = "#{player}의 체력이 0이 되어 전투가 종료됩니다."
      BattleState.say(msg)
      BattleState.end
    end
  end
end
