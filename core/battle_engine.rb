# core/battle_engine.rb
require 'securerandom'

require_relative 'battle_state'
require_relative '../sheet_manager'

class BattleEngine
  def initialize(client, sheet_manager)
    @client = client
    @sheet_manager = sheet_manager
  end

  # 1:1 전투 시작
  def start_battle(user_id, opponent_id, reply_status)
    participants = [user_id, opponent_id]
    
    # 선공 결정 (민첩성 + D20)
    user = @sheet_manager.find_user(user_id)
    opponent = @sheet_manager.find_user(opponent_id)
    
    user_dex = (user["민첩성"] || 10).to_i
    opponent_dex = (opponent["민첩성"] || 10).to_i
    
    user_init = user_dex + rand(1..20)
    opponent_init = opponent_dex + rand(1..20)
    
    # 턴 순서 결정 (높은 순서대로)
    turn_order = [[user_id, user_init], [opponent_id, opponent_init]]
                  .sort_by { |_, init| -init }
                  .map { |id, _| id }
    
    # visibility 가져오기
    visibility = get_visibility(reply_status)
    status_uri = get_status_uri(reply_status)
    
    # 전투 상태 생성
    battle_id = BattleState.create(
      participants,
      "pvp",
      status_uri,
      status_uri,
      visibility
    )
    
    state = BattleState.get(battle_id)
    state[:turn_order] = turn_order
    state[:current_turn] = turn_order.first
    state[:original_status] = reply_status
    BattleState.update(battle_id, state)
    
    user_name = user["이름"] || user_id
    opponent_name = opponent["이름"] || opponent_id
    
    # 참가자 태그 (ID와 이름)
    message = "@#{user_id} @#{opponent_id}\n\n"
    message += "전투 시작!\n\n"
    message += "#{user_name} (민첩: #{user_dex} + #{user_init - user_dex}) = #{user_init}\n"
    message += "#{opponent_name} (민첩: #{opponent_dex} + #{opponent_init - opponent_dex}) = #{opponent_init}\n\n"
    message += "턴 순서: #{turn_order.map { |id| get_user_name(id) }.join(' → ')}\n\n"
    message += show_all_hp(state)
    
    first_name = get_user_name(turn_order.first)
    message += "\n\n@#{turn_order.first} (#{first_name})\n"
    message += "[공격] [방어] [반격] [물약사용/크기]"
    
    reply_to_status(reply_status, message, visibility)
  end

  # 2:2 전투 시작
  def start_2v2_battle(team1, team2, reply_status)
    participants = team1 + team2
    
    # 팀별 민첩 합산 후 비교
    team1_dex_sum = team1.sum do |p|
      user = @sheet_manager.find_user(p)
      (user["민첩성"] || 10).to_i
    end
    
    team2_dex_sum = team2.sum do |p|
      user = @sheet_manager.find_user(p)
      (user["민첩성"] || 10).to_i
    end
    
    team1_init = team1_dex_sum + rand(1..20)
    team2_init = team2_dex_sum + rand(1..20)
    
    # 선공 팀 결정
    first_team = team1_init >= team2_init ? team1 : team2
    second_team = first_team == team1 ? team2 : team1
    
    # 각 팀 내에서 민첩 순서대로 정렬
    first_team_sorted = first_team.sort_by do |p|
      user = @sheet_manager.find_user(p)
      -(user["민첩성"] || 10).to_i
    end
    
    second_team_sorted = second_team.sort_by do |p|
      user = @sheet_manager.find_user(p)
      -(user["민첩성"] || 10).to_i
    end
    
    turn_order = first_team_sorted + second_team_sorted
    
    # visibility 가져오기
    visibility = get_visibility(reply_status)
    status_uri = get_status_uri(reply_status)
    
    battle_id = BattleState.create(
      participants,
      "2v2",
      status_uri,
      status_uri,
      visibility
    )
    
    state = BattleState.get(battle_id)
    state[:teams] = { team1: team1, team2: team2 }
    state[:turn_order] = turn_order
    state[:current_turn] = turn_order.first
    state[:original_status] = reply_status
    state[:protect] = {}  # 대리 방어 저장
    BattleState.update(battle_id, state)
    
    # 참가자 태그
    tags = participants.map { |p| "@#{p}" }.join(" ")
    message = "#{tags}\n\n"
    message += "2:2 전투 시작!\n\n"
    message += "팀1: #{team1.map { |id| get_user_name(id) }.join(', ')}\n"
    message += "팀2: #{team2.map { |id| get_user_name(id) }.join(', ')}\n\n"
    message += "턴 순서: #{turn_order.map { |id| get_user_name(id) }.join(' → ')}\n\n"
    message += show_all_hp(state)
    
    first_name = get_user_name(turn_order.first)
    message += "\n\n@#{turn_order.first} (#{first_name})\n"
    message += "[공격/@타겟] [방어/@아군] [반격] [물약사용/크기/@아군]"
    
    reply_to_status(reply_status, message, visibility)
  end

  # 4:4 전투 시작
  def start_4v4_battle(team1, team2, reply_status)
    participants = team1 + team2
    
    # 팀별 민첩 합산 후 비교
    team1_dex_sum = team1.sum do |p|
      user = @sheet_manager.find_user(p)
      (user["민첩성"] || 10).to_i
    end
    
    team2_dex_sum = team2.sum do |p|
      user = @sheet_manager.find_user(p)
      (user["민첩성"] || 10).to_i
    end
    
    team1_init = team1_dex_sum + rand(1..20)
    team2_init = team2_dex_sum + rand(1..20)
    
    # 선공 팀 결정
    first_team = team1_init >= team2_init ? team1 : team2
    second_team = first_team == team1 ? team2 : team1
    
    # 각 팀 내에서 민첩 순서대로 정렬
    first_team_sorted = first_team.sort_by do |p|
      user = @sheet_manager.find_user(p)
      -(user["민첩성"] || 10).to_i
    end
    
    second_team_sorted = second_team.sort_by do |p|
      user = @sheet_manager.find_user(p)
      -(user["민첩성"] || 10).to_i
    end
    
    turn_order = first_team_sorted + second_team_sorted
    
    # visibility 가져오기
    visibility = get_visibility(reply_status)
    status_uri = get_status_uri(reply_status)
    
    battle_id = BattleState.create(
      participants,
      "4v4",
      status_uri,
      status_uri,
      visibility
    )
    
    state = BattleState.get(battle_id)
    state[:teams] = { team1: team1, team2: team2 }
    state[:turn_order] = turn_order
    state[:current_turn] = turn_order.first
    state[:original_status] = reply_status
    state[:protect] = {}  # 대리 방어 저장
    BattleState.update(battle_id, state)
    
    # 참가자 태그
    tags = participants.map { |p| "@#{p}" }.join(" ")
    message = "#{tags}\n\n"
    message += "4:4 전투 시작!\n\n"
    message += "팀1: #{team1.map { |id| get_user_name(id) }.join(', ')}\n"
    message += "팀2: #{team2.map { |id| get_user_name(id) }.join(', ')}\n\n"
    message += "턴 순서: #{turn_order.map { |id| get_user_name(id) }.join(' → ')}\n\n"
    message += show_all_hp(state)
    
    first_name = get_user_name(turn_order.first)
    message += "\n\n@#{turn_order.first} (#{first_name})\n"
    message += "[공격/@타겟] [방어/@아군] [반격] [물약사용/크기/@아군]"
    
    reply_to_status(reply_status, message, visibility)
  end

  # 액션 등록
  def register_action(user_id, action_type, target_id, battle_id, potion_size = nil)
    state = BattleState.get(battle_id)
    return unless state
    
    # 현재 턴 확인
    if state[:current_turn] != user_id
      tags = state[:participants].map { |p| "@#{p}" }.join(" ")
      message = "#{tags}\n\n"
      message += "@#{user_id} 당신의 차례가 아닙니다.\n\n"
      current_name = get_user_name(state[:current_turn])
      message += "현재 턴: @#{state[:current_turn]} (#{current_name})"
      reply_to_state(state, message)
      return
    end
    
    # 액션 저장
    state[:actions] ||= {}
    state[:actions][user_id] = {
      type: action_type,
      target: target_id,
      potion_size: potion_size
    }
    
    user_name = get_user_name(user_id)
    
    # 턴 순서에서 다음 살아있는 플레이어 찾기
    turn_order = state[:turn_order] || state[:participants]
    current_index = turn_order.index(user_id)
    
    next_player = nil
    tried = 0
    
    while tried < turn_order.length
      next_index = (current_index + 1 + tried) % turn_order.length
      next_id = turn_order[next_index]
      
      # 이미 선택했거나 죽은 플레이어는 건너뛰기
      next_user = @sheet_manager.find_user(next_id)
      if !state[:actions].key?(next_id) && (next_user["HP"] || 0).to_i > 0
        next_player = next_id
        break
      end
      
      tried += 1
    end
    
    tags = state[:participants].map { |p| "@#{p}" }.join(" ")
    message = "#{tags}\n\n"
    message += "#{user_name}이(가) 행동을 선택했습니다.\n\n"
    
    if next_player
      # 다음 플레이어의 턴
      state[:current_turn] = next_player
      BattleState.update(battle_id, state)
      
      next_name = get_user_name(next_player)
      message += "@#{next_player} (#{next_name})\n"
      
      if state[:type] == "pvp"
        message += "[공격] [방어] [반격] [물약사용/크기]"
      else
        message += "[공격/@타겟] [방어/@아군] [반격] [물약사용/크기/@아군]"
      end
      
      reply_to_state(state, message)
    else
      # 모두 선택 완료 → 라운드 처리
      BattleState.update(battle_id, state)
      process_round(state, battle_id)
    end
  end

  private

  # 라운드 처리 (우선순위: 물약 > 반격 설정 > 방어 > 공격+반격 판정)
  def process_round(state, battle_id)
    actions = state[:actions]
    messages = []
    
    tags = state[:participants].map { |p| "@#{p}" }.join(" ")
    
    # 우선순위 1: 물약 사용
    potion_actions = actions.select { |_, action| action[:type] == :use_potion }
    potion_actions.each do |user_id, action|
      result = execute_potion(user_id, action[:potion_size], action[:target], state, battle_id)
      messages << result if result
    end
    
    # 우선순위 2: 반격 태세 설정
    counter_actions = actions.select { |_, action| action[:type] == :counter }
    counter_actions.each do |user_id, action|
      state[:counter_stance] ||= {}
      state[:counter_stance][user_id] = true
      messages << "#{get_user_name(user_id)}이(가) 반격 태세!"
    end
    
    # 우선순위 3: 방어 태세 / 대리 방어
    defend_actions = actions.select { |_, action| action[:type] == :defend }
    defend_actions.each do |user_id, action|
      target_id = action[:target]
      
      if target_id && target_id != user_id
        # 대리 방어 (팀전)
        state[:protect] ||= {}
        state[:protect][target_id] = user_id
        messages << "#{get_user_name(user_id)}이(가) #{get_user_name(target_id)}을(를) 대리 방어!"
      else
        # 자신 방어
        state[:guarded][user_id] = true
        messages << "#{get_user_name(user_id)}이(가) 방어 태세!"
      end
    end
    
    # 우선순위 4: 공격 (턴 순서대로) + 반격 판정
    attack_actions = actions.select { |_, action| action[:type] == :attack }
    turn_order = state[:turn_order] || state[:participants]
    
    turn_order.each do |user_id|
      next unless attack_actions.key?(user_id)
      
      action = attack_actions[user_id]
      target_id = action[:target]
      
      # 공격자와 피해자가 살아있는지 확인
      attacker = @sheet_manager.find_user(user_id)
      defender = @sheet_manager.find_user(target_id)
      
      next if (attacker["HP"] || 0).to_i <= 0
      next if (defender["HP"] || 0).to_i <= 0
      
      # 팀전에서 같은 팀 공격 방지
      if state[:type] == "2v2" || state[:type] == "4v4"
        user_team = state[:teams][:team1].include?(user_id) ? :team1 : :team2
        target_team = state[:teams][:team1].include?(target_id) ? :team1 : :team2
        
        if user_team == target_team
          messages << "#{get_user_name(user_id)}의 공격 실패 (아군 공격 불가)"
          next
        end
      end
      
      # 대리 방어 확인
      actual_defender_id = target_id
      actual_defender = defender
      
      if state[:protect] && state[:protect][target_id]
        protector_id = state[:protect][target_id]
        protector = @sheet_manager.find_user(protector_id)
        
        if (protector["HP"] || 0).to_i > 0
          actual_defender_id = protector_id
          actual_defender = protector
          messages << "#{get_user_name(protector_id)}이(가) #{get_user_name(target_id)}을(를) 대신 방어!"
        end
      end
      
      # 공격 실행
      result = execute_attack(attacker, user_id, actual_defender, actual_defender_id, state, battle_id)
      
      attack_msg = "#{get_user_name(user_id)}의 공격 → #{get_user_name(actual_defender_id)}\n"
      attack_msg += "공격: #{result[:atk]} + D20(#{result[:atk_roll]}) = #{result[:atk_total]}"
      attack_msg += " [치명타!]" if result[:is_crit]
      attack_msg += "\n"
      attack_msg += "방어: #{result[:def]} + D20(#{result[:def_roll]})"
      attack_msg += " + D20(#{result[:def_bonus]})" if result[:def_bonus] > 0
      attack_msg += " = #{result[:def_total]}\n"
      
      if result[:damage] > 0
        attack_msg += "#{result[:damage]} 피해! (HP: #{result[:old_hp]} → #{result[:new_hp]})"
      else
        attack_msg += "공격 실패!"
      end
      
      messages << attack_msg
      
      # 반격 판정 (피해자가 반격 태세였다면)
      if state[:counter_stance] && state[:counter_stance][actual_defender_id] && result[:damage] > 0
        counter_result = execute_counter(actual_defender, actual_defender_id, attacker, user_id, result[:atk_total], state, battle_id)
        
        counter_msg = "\n#{get_user_name(actual_defender_id)}의 반격 판정!\n"
        counter_msg += "반격: #{counter_result[:counter_atk]} + D20(#{counter_result[:counter_roll]}) = #{counter_result[:counter_total]}\n"
        counter_msg += "공격력: #{result[:atk_total]}\n"
        
        if counter_result[:success]
          counter_msg += "반격 성공! #{counter_result[:counter_damage]} 피해! (HP: #{counter_result[:old_hp]} → #{counter_result[:new_hp]})"
        else
          counter_msg += "반격 실패..."
        end
        
        messages << counter_msg
        
        # 반격 태세 해제
        state[:counter_stance].delete(actual_defender_id)
      end
    end
    
    # 라운드 결과 출력
    message = "#{tags}\n\n"
    message += "━━━━━━ 라운드 #{state[:round]} ━━━━━━\n\n"
    message += messages.join("\n\n")
    message += "\n\n" + show_all_hp(state)
    
    # 승패 확인
    if check_battle_end(state, battle_id, message)
      return
    end
    
    # 다음 라운드 준비
    state[:round] += 1
    state[:actions] = {}
    state[:guarded] = {}
    state[:counter_stance] = {}
    state[:protect] = {}
    
    # 첫 번째 살아있는 플레이어부터 시작
    turn_order = state[:turn_order] || state[:participants]
    next_first = turn_order.find do |p|
      user = @sheet_manager.find_user(p)
      (user["HP"] || 0).to_i > 0
    end
    
    state[:current_turn] = next_first
    BattleState.update(battle_id, state)
    
    message += "\n\n━━━━━━ 다음 라운드 ━━━━━━\n\n"
    
    if next_first
      next_name = get_user_name(next_first)
      message += "@#{next_first} (#{next_name})\n"
      
      if state[:type] == "pvp"
        message += "[공격] [방어] [반격] [물약사용/크기]"
      else
        message += "[공격/@타겟] [방어/@아군] [반격] [물약사용/크기/@아군]"
      end
    end
    
    reply_to_state(state, message)
  end

  # 승패 확인
  def check_battle_end(state, battle_id, current_message)
    if state[:type] == "pvp"
      # 1:1 전투
      alive = state[:participants].select do |p|
        user = @sheet_manager.find_user(p)
        (user["HP"] || 0).to_i > 0
      end
      
      if alive.length == 1
        winner_name = get_user_name(alive.first)
        current_message += "\n\n#{winner_name} 승리!"
        reply_to_state(state, current_message)
        BattleState.clear(battle_id)
        return true
      elsif alive.length == 0
        current_message += "\n\n무승부!"
        reply_to_state(state, current_message)
        BattleState.clear(battle_id)
        return true
      end
    else
      # 팀전
      team1_alive = state[:teams][:team1].any? do |p|
        user = @sheet_manager.find_user(p)
        (user["HP"] || 0).to_i > 0
      end
      
      team2_alive = state[:teams][:team2].any? do |p|
        user = @sheet_manager.find_user(p)
        (user["HP"] || 0).to_i > 0
      end
      
      if !team1_alive && !team2_alive
        current_message += "\n\n무승부!"
        reply_to_state(state, current_message)
        BattleState.clear(battle_id)
        return true
      elsif !team1_alive
        current_message += "\n\n팀2 승리!"
        reply_to_state(state, current_message)
        BattleState.clear(battle_id)
        return true
      elsif !team2_alive
        current_message += "\n\n팀1 승리!"
        reply_to_state(state, current_message)
        BattleState.clear(battle_id)
        return true
      end
    end
    
    false
  end

  # 공격 실행
  def execute_attack(attacker, attacker_id, defender, defender_id, state, battle_id)
    atk = (attacker["공격"] || 10).to_i
    def_stat = (defender["방어"] || 10).to_i
    luck = (attacker["행운"] || 10).to_i
    
    atk_roll = rand(1..20)
    def_roll = rand(1..20)
    def_bonus = 0
    
    # 치명타 (행운 2당 5%, 최대 50%)
    crit_chance = [(luck / 2.0 * 5).to_i, 50].min
    is_crit = rand(1..100) <= crit_chance
    
    atk_total = atk + atk_roll
    
    # 방어 태세 확인 (D20 보너스 추가)
    if state[:guarded][defender_id]
      def_bonus = rand(1..20)
    end
    
    def_total = def_stat + def_roll + def_bonus
    
    # 치명타 적용 (데미지에)
    base_damage = [atk_total - def_total, 0].max
    damage = is_crit ? (base_damage * 1.5).to_i : base_damage
    
    old_hp = (defender["HP"] || 100).to_i
    new_hp = [old_hp - damage, 0].max
    
    @sheet_manager.update_user(defender_id, { "HP" => new_hp })
    
    {
      atk: atk,
      atk_roll: atk_roll,
      atk_total: atk_total,
      def: def_stat,
      def_roll: def_roll,
      def_bonus: def_bonus,
      def_total: def_total,
      damage: damage,
      old_hp: old_hp,
      new_hp: new_hp,
      is_crit: is_crit
    }
  end

  # 반격 실행
  def execute_counter(counter_user, counter_id, attacker, attacker_id, attack_total, state, battle_id)
    counter_atk = (counter_user["공격"] || 10).to_i
    counter_roll = rand(1..20)
    counter_total = counter_atk + counter_roll
    
    success = counter_total > attack_total
    
    if success
      counter_damage = counter_total - attack_total
      old_hp = (attacker["HP"] || 100).to_i
      new_hp = [old_hp - counter_damage, 0].max
      
      @sheet_manager.update_user(attacker_id, { "HP" => new_hp })
      
      {
        success: true,
        counter_atk: counter_atk,
        counter_roll: counter_roll,
        counter_total: counter_total,
        counter_damage: counter_damage,
        old_hp: old_hp,
        new_hp: new_hp
      }
    else
      {
        success: false,
        counter_atk: counter_atk,
        counter_roll: counter_roll,
        counter_total: counter_total
      }
    end
  end

  # 물약 사용 실행
  def execute_potion(user_id, potion_size, target_id, state, battle_id)
    user = @sheet_manager.find_user(user_id)
    items_str = user["아이템"] || ""
    items = parse_items(items_str)
    
    potion_key = case potion_size
    when "소형" then "소형물약"
    when "중형" then "중형물약"
    when "대형" then "대형물약"
    else
      return "#{get_user_name(user_id)}: 알 수 없는 물약"
    end
    
    return "#{get_user_name(user_id)}: #{potion_key} 없음" unless items[potion_key] && items[potion_key] > 0
    
    heal_amount = case potion_key
    when "소형물약" then 10
    when "중형물약" then 30
    when "대형물약" then 50
    end
    
    heal_target_id = target_id || user_id
    heal_target = @sheet_manager.find_user(heal_target_id)
    
    current_hp = (heal_target["HP"] || 0).to_i
    max_hp = 100 + ((heal_target["체력"] || 10).to_i * 10)
    new_hp = [current_hp + heal_amount, max_hp].min
    actual_heal = new_hp - current_hp
    
    @sheet_manager.update_user(heal_target_id, { "HP" => new_hp })
    
    # 물약 감소
    items[potion_key] -= 1
    items.delete(potion_key) if items[potion_key] <= 0
    new_items_str = items.map { |k, v| "#{k}:#{v}" }.join(", ")
    @sheet_manager.update_user(user_id, { "아이템" => new_items_str })
    
    if user_id == heal_target_id
      "#{get_user_name(user_id)}: #{potion_key} 사용 (HP +#{actual_heal})"
    else
      "#{get_user_name(user_id)} → #{get_user_name(heal_target_id)}: #{potion_key} (HP +#{actual_heal})"
    end
  end

  # 아이템 파싱
  def parse_items(items_str)
    items = {}
    return items if items_str.nil? || items_str.strip.empty?
    
    items_str.split(',').each do |item|
      parts = item.strip.split(':')
      next if parts.length != 2
      
      name = parts[0].strip
      count = parts[1].strip.to_i
      items[name] = count if count > 0
    end
    
    items
  end

  # 최대 HP 계산
  def calculate_max_hp(user)
    vitality = (user["체력"] || 10).to_i
    base_hp = 100
    max_hp = base_hp + (vitality * 10)
    max_hp
  end

  # 체력바 생성
  def generate_hp_bar(current_hp, max_hp)
    return "██████████" if current_hp >= max_hp
    return "░░░░░░░░░░" if current_hp <= 0 || max_hp <= 0
    
    hp_percent = (current_hp.to_f / max_hp.to_f * 100).round
    filled = (hp_percent / 10.0).floor
    empty = 10 - filled
    
    "█" * filled + "░" * empty
  end

  # 전체 참가자 체력 표시
  def show_all_hp(state)
    message = "━━━━━━━━━━━━━━━━━━\n"
    message += "현재 체력\n"
    
    state[:participants].each do |participant_id|
      participant = @sheet_manager.find_user(participant_id)
      next unless participant
      
      name = participant["이름"] || participant_id
      current_hp = (participant["HP"] || 0).to_i
      max_hp = calculate_max_hp(participant)
      hp_bar = generate_hp_bar(current_hp, max_hp)
      
      message += "#{name}: #{current_hp}/#{max_hp} #{hp_bar}\n"
    end
    
    message += "━━━━━━━━━━━━━━━━━━"
    message
  end

  # 사용자 이름 가져오기
  def get_user_name(user_id)
    user = @sheet_manager.find_user(user_id)
    user ? (user["이름"] || user_id) : user_id
  end

  # Visibility 가져오기
  def get_visibility(status)
    if status.respond_to?(:visibility)
      status.visibility
    elsif status.is_a?(Hash)
      status['visibility'] || status[:visibility] || 'public'
    else
      'public'
    end
  end

  # Status URI 가져오기
  def get_status_uri(status)
    if status.respond_to?(:uri)
      status.uri
    elsif status.respond_to?(:id)
      status.id.to_s
    elsif status.is_a?(Hash)
      status['uri'] || status[:uri] || status['id'] || status[:id]
    else
      nil
    end
  end

  # Status에 응답
  def reply_to_status(status, message, visibility = nil)
    use_visibility = visibility || get_visibility(status)
    @client.reply(status, message, visibility: use_visibility)
  end

  # State에서 응답
  def reply_to_state(state, message)
    original_status = state[:original_status]
    visibility = state[:visibility] || 'public'
    
    if original_status
      reply_to_status(original_status, message, visibility)
    else
      status = {
        'id' => state[:thread_ts],
        'visibility' => visibility
      }
      @client.reply(status, message, visibility: visibility)
    end
  end
end
