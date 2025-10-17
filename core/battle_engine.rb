# core/battle_engine.rb
require_relative 'battle_state'

module BattleEngine
  module_function

  @@sheet_manager = nil
  @@scarecrow_stats = {
    "허수아비_하" => { "체력" => 60, "공격력" => 3, "방어력" => 3, "민첩" => 3 },
    "허수아비_중" => { "체력" => 80, "공격력" => 4, "방어력" => 4, "민첩" => 4 },
    "허수아비_상" => { "체력" => 100, "공격력" => 5, "방어력" => 5, "민첩" => 5 }
  }

  def set_sheet_manager(sheet_manager)
    @@sheet_manager = sheet_manager
  end

  def init_1v1(players)
    BattleState.set(players: players, turn: nil)
  end

  def init_scarecrow_battle(players, difficulty)
    BattleState.set(players: players, turn: nil, scarecrow: true, difficulty: difficulty)
  end

  def init_multi_battle(team_a, team_b)
    BattleState.set(players: team_a + team_b, team_a: team_a, team_b: team_b, turn: nil)
  end

  def init_team_battle(team_a, team_b)
    BattleState.set(players: team_a + team_b, team_a: team_a, team_b: team_b, turn: nil)
  end

  def roll_initiative(players)
    stats = players.map do |p|
      agility = get_stat_value(p, "민첩")
      [p, agility + rand(1..20)]
    end
    sorted = stats.sort_by { |_, roll| -roll }

    BattleState.set_turn(sorted[0][0])
    msg = "선공 #{sorted[0][0]}, 후공 #{sorted[1][0]} 전투를 시작합니다."
    BattleState.say(msg)
    
    if sorted[0][0].include?("허수아비")
      scarecrow_ai_action(sorted[0][0])
    end
  end

  def roll_team_initiative(team_a, team_b)
    a_total = team_a.sum do |p|
      agility = get_stat_value(p, "민첩")
      agility
    end / team_a.size + rand(1..20)
    
    b_total = team_b.sum do |p|
      agility = get_stat_value(p, "민첩")
      agility
    end / team_b.size + rand(1..20)

    first_team = a_total >= b_total ? team_a : team_b
    BattleState.set_turn(first_team[0])
    msg = "선공 팀 (#{first_team.join(", ")}), 후공 팀 (#{(first_team == team_a ? team_b : team_a).join(", ")}) 전투를 시작합니다."
    BattleState.say(msg)
  end

  def get_stat_value(player, stat_name)
    if player.include?("허수아비")
      raw_value = @@scarecrow_stats[player][stat_name] || 3
    else
      stat = @@sheet_manager.get_stat(player, stat_name)
      raw_value = stat ? stat.to_i : 3
    end
    
    # 공격력, 방어력, 민첩 스탯을 1~5 범위로 제한
    if ["공격력", "방어력", "민첩"].include?(stat_name)
      return [[raw_value, 1].max, 5].min
    end
    
    # 체력과 기타 스탯은 제한 없음
    return raw_value
  end

  def attack(user)
    unless BattleState.is_current_turn?(user)
      BattleState.say("#{user}님의 턴이 아닙니다.")
      return
    end

    BattleState.cancel_turn_timer

    defender = BattleState.get_opponent(user)
    
    atk_stat = get_stat_value(user, "공격력")
    def_stat = get_stat_value(defender, "방어력")
    
    atk = atk_stat + rand(1..20)
    def_val = def_stat + rand(1..20)

    dmg = [atk - def_val, 0].max
    
    if defender.include?("허수아비")
      current_hp = @@scarecrow_stats[defender]["체력"]
      new_hp = current_hp - dmg
      @@scarecrow_stats[defender]["체력"] = new_hp
      
      msg = "#{user}의 공격! #{defender}에게 #{dmg} 피해를 입혔습니다.\n"
      msg += "#{user}의 공격 : #{atk}, #{defender}의 방어 #{def_val}\n"
      
      user_hp = get_stat_value(user, "체력")
      msg += "남은 체력 - #{user}: #{user_hp} / #{defender}: #{new_hp}"
    else
      hp_stat = @@sheet_manager.get_stat(defender, "체력")
      current_hp = hp_stat ? hp_stat.to_i : 100
      new_hp = current_hp - dmg
      
      @@sheet_manager.set_stat(defender, "체력", new_hp)

      msg = "#{user}의 공격! #{defender}에게 #{dmg} 피해를 입혔습니다.\n"
      msg += "#{user}의 공격 : #{atk}, #{defender}의 방어 #{def_val}\n"
      
      user_hp = get_stat_value(user, "체력")
      msg += "남은 체력 - #{user}: #{user_hp} / #{defender}: #{new_hp}"
    end

    BattleState.say(msg)

    check_ending(defender)
    BattleState.next_turn
    
    next_player = BattleState.get_turn
    if next_player && next_player.include?("허수아비")
      scarecrow_ai_action(next_player)
    end
  end

  def defend(user)
    unless BattleState.is_current_turn?(user)
      BattleState.say("#{user}님의 턴이 아닙니다.")
      return
    end

    BattleState.cancel_turn_timer

    msg = "#{user}이(가) 방어 자세를 취합니다. 다음 턴으로 넘어갑니다."
    BattleState.say(msg)
    BattleState.next_turn
    
    next_player = BattleState.get_turn
    if next_player && next_player.include?("허수아비")
      scarecrow_ai_action(next_player)
    end
  end

  def counter(user)
    unless BattleState.is_current_turn?(user)
      BattleState.say("#{user}님의 턴이 아닙니다.")
      return
    end

    BattleState.cancel_turn_timer

    attacker = BattleState.get_opponent(user)
    
    counter_stat = get_stat_value(user, "공격력")
    def_stat = get_stat_value(attacker, "방어력")
    
    counter = counter_stat + rand(1..20)
    def_val = def_stat + rand(1..20)

    dmg = [counter - def_val, 0].max
    
    if attacker.include?("허수아비")
      current_hp = @@scarecrow_stats[attacker]["체력"]
      new_hp = current_hp - dmg
      @@scarecrow_stats[attacker]["체력"] = new_hp
      
      msg = "#{user}의 반격! #{attacker}에게 #{dmg} 피해를 입혔습니다.\n"
      msg += "#{user}의 반격 #{counter}, #{attacker}의 방어 #{def_val}\n"
      
      user_hp = get_stat_value(user, "체력")
      msg += "남은 체력 - #{attacker}: #{new_hp} / #{user}: #{user_hp}"
    else
      hp_stat = @@sheet_manager.get_stat(attacker, "체력")
      current_hp = hp_stat ? hp_stat.to_i : 100
      new_hp = current_hp - dmg
      
      @@sheet_manager.set_stat(attacker, "체력", new_hp)

      msg = "#{user}의 반격! #{attacker}에게 #{dmg} 피해를 입혔습니다.\n"
      msg += "#{user}의 반격 #{counter}, #{attacker}의 방어 #{def_val}\n"
      
      user_hp = get_stat_value(user, "체력")
      msg += "남은 체력 - #{attacker}: #{new_hp} / #{user}: #{user_hp}"
    end

    BattleState.say(msg)

    check_ending(attacker)
    BattleState.next_turn
    
    next_player = BattleState.get_turn
    if next_player && next_player.include?("허수아비")
      scarecrow_ai_action(next_player)
    end
  end

  def escape(user)
    unless BattleState.is_current_turn?(user)
      BattleState.say("#{user}님의 턴이 아닙니다.")
      return
    end

    BattleState.cancel_turn_timer

    opp = BattleState.get_opponent(user)
    
    luck_stat = @@sheet_manager.get_stat(user, "행운")
    agi_stat = @@sheet_manager.get_stat(user, "민첩")
    
    luck = luck_stat ? luck_stat.to_i : 3
    agi = agi_stat ? agi_stat.to_i : 3
    opp_agi = get_stat_value(opp, "민첩")
    
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
      
      next_player = BattleState.get_turn
      if next_player && next_player.include?("허수아비")
        scarecrow_ai_action(next_player)
      end
    end
  end

  def use_potion(user)
    unless BattleState.is_current_turn?(user)
      BattleState.say("#{user}님의 턴이 아닙니다.")
      return
    end

    BattleState.cancel_turn_timer

    amount = [5, 10, 15, 20].sample
    
    if user.include?("허수아비")
      current_hp = @@scarecrow_stats[user]["체력"]
      new_hp = [current_hp + amount, 100].min
      @@scarecrow_stats[user]["체력"] = new_hp
    else
      hp_stat = @@sheet_manager.get_stat(user, "체력")
      cur_hp = hp_stat ? hp_stat.to_i : 100
      new_hp = [cur_hp + amount, 100].min
      @@sheet_manager.set_stat(user, "체력", new_hp)
    end
    
    msg = "#{user}의 체력이 #{amount} 회복되었습니다. 현재 체력 #{new_hp}"
    BattleState.say(msg)
    BattleState.next_turn
    
    next_player = BattleState.get_turn
    if next_player && next_player.include?("허수아비")
      scarecrow_ai_action(next_player)
    end
  end

  def check_ending(defender)
    hp = if defender.include?("허수아비")
      @@scarecrow_stats[defender]["체력"]
    else
      hp_stat = @@sheet_manager.get_stat(defender, "체력")
      hp_stat ? hp_stat.to_i : 100
    end

    if hp <= 0
      msg = "#{defender}의 체력이 0이 되었습니다. 전투 종료!"
      BattleState.say(msg)
      BattleState.end
    end
  end

  def scarecrow_ai_action(scarecrow_id)
    actions = [:ai_attack, :ai_defend, :ai_counter, :ai_use_potion]
    selected = actions.sample
    
    send(selected, scarecrow_id)
  end

  def ai_attack(scarecrow_id)
    defender = BattleState.get_opponent(scarecrow_id)
    
    atk_stat = get_stat_value(scarecrow_id, "공격력")
    def_stat = get_stat_value(defender, "방어력")
    
    atk = atk_stat + rand(1..20)
    def_val = def_stat + rand(1..20)

    dmg = [atk - def_val, 0].max
    
    hp_stat = @@sheet_manager.get_stat(defender, "체력")
    current_hp = hp_stat ? hp_stat.to_i : 100
    new_hp = current_hp - dmg
    
    @@sheet_manager.set_stat(defender, "체력", new_hp)

    msg = "#{scarecrow_id}의 공격! #{defender}에게 #{dmg} 피해를 입혔습니다.\n"
    msg += "#{scarecrow_id}의 공격 : #{atk}, #{defender}의 방어 #{def_val}\n"
    
    scarecrow_hp = @@scarecrow_stats[scarecrow_id]["체력"]
    msg += "남은 체력 - #{scarecrow_id}: #{scarecrow_hp} / #{defender}: #{new_hp}"

    BattleState.say(msg)

    check_ending(defender)
    BattleState.next_turn
  end

  def ai_defend(scarecrow_id)
    msg = "#{scarecrow_id}이(가) 방어 자세를 취합니다. 다음 턴으로 넘어갑니다."
    BattleState.say(msg)
    BattleState.next_turn
  end

  def ai_counter(scarecrow_id)
    attacker = BattleState.get_opponent(scarecrow_id)
    
    counter_stat = get_stat_value(scarecrow_id, "공격력")
    def_stat = get_stat_value(attacker, "방어력")
    
    counter = counter_stat + rand(1..20)
    def_val = def_stat + rand(1..20)

    dmg = [counter - def_val, 0].max
    
    hp_stat = @@sheet_manager.get_stat(attacker, "체력")
    current_hp = hp_stat ? hp_stat.to_i : 100
    new_hp = current_hp - dmg
    
    @@sheet_manager.set_stat(attacker, "체력", new_hp)

    msg = "#{scarecrow_id}의 반격! #{attacker}에게 #{dmg} 피해를 입혔습니다.\n"
    msg += "#{scarecrow_id}의 반격 #{counter}, #{attacker}의 방어 #{def_val}\n"
    
    scarecrow_hp = @@scarecrow_stats[scarecrow_id]["체력"]
    msg += "남은 체력 - #{attacker}: #{new_hp} / #{scarecrow_id}: #{scarecrow_hp}"

    BattleState.say(msg)

    check_ending(attacker)
    BattleState.next_turn
  end

  def ai_use_potion(scarecrow_id)
    amount = [5, 10, 15, 20].sample
    current_hp = @@scarecrow_stats[scarecrow_id]["체력"]
    new_hp = [current_hp + amount, 100].min
    @@scarecrow_stats[scarecrow_id]["체력"] = new_hp
    
    msg = "#{scarecrow_id}의 체력이 #{amount} 회복되었습니다. 현재 체력 #{new_hp}"
    BattleState.say(msg)
    BattleState.next_turn
  end
end
