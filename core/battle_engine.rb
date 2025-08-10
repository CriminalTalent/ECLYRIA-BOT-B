# core/battle_engine.rb
require_relative 'battle_state'

module BattleEngine
  module_function

  @@sheet_manager = nil
  @@scarecrow_stats = {
    "허수아비_하" => { "체력" => 60, "공격력" => 8, "방어력" => 6, "민첩" => 8 },
    "허수아비_중" => { "체력" => 80, "공격력" => 12, "방어력" => 10, "민첩" => 12 },
    "허수아비_상" => { "체력" => 100, "공격력" => 16, "방어력" => 14, "민첩" => 16 }
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
    
    # 허수아비가 선공이면 즉시 AI 행동
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
    BattleState.set_turn(first_team[0]) # 팀의 첫 번째 플레이어
    msg = "선공 팀 (#{first_team.join(", ")}), 후공 팀 (#{(first_team == team_a ? team_b : team_a).join(", ")}) 전투를 시작합니다."
    BattleState.say(msg)
  end

  def get_stat_value(player, stat_name)
    if player.include?("허수아비")
      return @@scarecrow_stats[player][stat_name] || 10
    else
      stat = @@sheet_manager.get_stat(player, stat_name)
      return stat ? stat.to_i : 10
    end
  end

  def attack(user)
    unless BattleState.is_current_turn?(user)
      BattleState.say("#{user}님의 턴이 아닙니다.")
      return
    end

    # 사용자가 행동했으므로 타이머 취소
    BattleState.cancel_turn_timer

    defender = BattleState.get_opponent(user)
    
    atk_stat = get_stat_value(user, "공격력")
    def_stat = get_stat_value(defender, "방어력")
    
    atk = atk_stat + rand(1..20)
    def_val = def_stat + rand(1..20)

    dmg = [atk - def_val, 0].max
    
    if defender.include?("허수아비")
      # 허수아비 체력 처리
      current_hp = @@scarecrow_stats[defender]["체력"]
      new_hp = current_hp - dmg
      @@scarecrow_stats[defender]["체력"] = new_hp
      
      msg = "#{user}의 공격! #{defender}에게 #{dmg} 피해를 입혔습니다.\n"
      msg += "#{user}의 공격 : #{atk}, #{defender}의 방어 #{def_val}\n"
      
      user_hp = get_stat_value(user, "체력")
      msg += "남은 체력 - #{user}: #{user_hp} / #{defender}: #{new_hp}"
    else
      # 일반 플레이어 체력 처리
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
    
    # 다음 턴이 허수아비면 AI 행동
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

    # 사용자가 행동했으므로 타이머 취소
    BattleState.cancel_turn_timer

    msg = "#{user}이(가) 방어 자세를 취합니다. 다음 턴으로 넘어갑니다."
    BattleState.say(msg)
    BattleState.next_turn
    
    # 다음 턴이 허수아비면 AI 행동
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

    # 사용자가 행동했으므로 타이머 취소
    BattleState.cancel_turn_timer

    attacker = BattleState.get_opponent(user)
    
    counter_stat = get_stat_value(user, "공격력")
    def_stat = get_stat_value(attacker, "방어력")
    
    counter = counter_stat + rand(1..20)
    def_val = def_stat + rand(1..20)

    dmg = [counter - def_val, 0].max
    
    if attacker.include?("허수아비")
      # 허수아비 체력 처리
      current_hp = @@scarecrow_stats[attacker]["체력"]
      new_hp = current_hp - dmg
      @@scarecrow_stats[attacker]["체력"] = new_hp
      
      msg = "#{user}의 반격! #{attacker}에게 #{dmg} 피해를 입혔습니다.\n"
      msg += "#{user}의 반격 #{counter}, #{attacker}의 방어 #{def_val}\n"
      
      user_hp = get_stat_value(user, "체력")
      msg += "남은 체력 - #{attacker}: #{new_hp} / #{user}: #{user_hp}"
    else
      # 일반 플레이어 체력 처리
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
    
    # 다음 턴이 허수아비면 AI 행동
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

    # 사용자가 행동했으므로 타이머 취소
    BattleState.cancel_turn_timer

    opp = BattleState.get_opponent(user)
    
    luck_stat = @@sheet_manager.get_stat(user, "행운")
    agi_stat = @@sheet_manager.get_stat(user, "민첩")
    
    luck = luck_stat ? luck_stat.to_i : 10
    agi = agi_stat ? agi_stat.to_i : 10
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
      
      # 다음 턴이 허수아비면 AI 행동
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

    # 사용자가 행동했으므로 타이머 취소
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
    
    # 다음 턴이 허수아비면 AI 행동
    next_player = BattleState.get_turn
    if next_player && next_player.include?("허수아비")
      scarecrow_ai_action(next_player)
    end
  end

  def check_ending(player)
    hp = if player.include?("허수아비")
      @@scarecrow_stats[player]["체력"]
    else
      hp_stat = @@sheet_manager.get_stat(player, "체력")
      hp_stat ? hp_stat.to_i : 100
    end
    
    if hp <= 0
      msg = "#{player}의 체력이 0이 되어 전투가 종료됩니다."
      BattleState.say(msg)
      BattleState.end
    end
  end

  # 허수아비 AI 행동 패턴
  def scarecrow_ai_action(scarecrow_id)
    sleep(2) # 2초 대기로 자연스러운 느낌
    
    # 허수아비의 난이도에 따른 행동 패턴
    difficulty = scarecrow_id.split("_")[1]
    
    case difficulty
    when "하"
      # 70% 공격, 20% 방어, 10% 물약
      action = rand(100) < 70 ? "공격" : (rand(100) < 80 ? "방어" : "물약사용")
    when "중"
      # 60% 공격, 25% 방어, 10% 반격, 5% 물약
      rand_val = rand(100)
      action = if rand_val < 60
        "공격"
      elsif rand_val < 85
        "방어"
      elsif rand_val < 95
        "반격"
      else
        "물약사용"
      end
    when "상"
      # 50% 공격, 20% 방어, 25% 반격, 5% 물약
      rand_val = rand(100)
      action = if rand_val < 50
        "공격"
      elsif rand_val < 70
        "방어"
      elsif rand_val < 95
        "반격"
      else
        "물약사용"
      end
    end

    # AI 행동 실행
    case action
    when "공격"
      ai_attack(scarecrow_id)
    when "방어"  
      ai_defend(scarecrow_id)
    when "반격"
      ai_counter(scarecrow_id)
    when "물약사용"
      ai_use_potion(scarecrow_id)
    end
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
