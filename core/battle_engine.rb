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
    
    user_dex = (user["민첩성"] || user[:dexterity] || 10).to_i
    opponent_dex = (opponent["민첩성"] || opponent[:dexterity] || 10).to_i
    
    user_init = user_dex + rand(1..20)
    opponent_init = opponent_dex + rand(1..20)
    
    first_attacker = user_init >= opponent_init ? user_id : opponent_id
    
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
    state[:current_turn] = first_attacker
    state[:original_status] = reply_status
    BattleState.update(battle_id, state)
    
    user_name = user["이름"] || user_id
    opponent_name = opponent["이름"] || opponent_id
    
    # 참가자 태그
    message = "@#{user_id} @#{opponent_id}\n\n"
    message += "전투 시작!\n\n"
    message += "#{user_name} (민첩: #{user_dex} + #{user_init - user_dex}) = #{user_init}\n"
    message += "#{opponent_name} (민첩: #{opponent_dex} + #{opponent_init - opponent_dex}) = #{opponent_init}\n\n"
    message += "#{first_attacker == user_id ? user_name : opponent_name}의 선공!\n\n"
    message += show_all_hp(state)
    message += "\n\n@#{first_attacker}\n"
    message += "[공격] [방어] [반격] [물약사용/크기]"
    
    reply_to_status(reply_status, message, visibility)
  end

  # 2:2 전투 시작
  def start_2v2_battle(team1, team2, reply_status)
    participants = team1 + team2
    
    # 팀 민첩 합계 계산
    team1_dex = team1.sum do |p|
      user = @sheet_manager.find_user(p)
      (user["민첩성"] || user[:dexterity] || 10).to_i
    end
    
    team2_dex = team2.sum do |p|
      user = @sheet_manager.find_user(p)
      (user["민첩성"] || user[:dexterity] || 10).to_i
    end
    
    team1_init = team1_dex + rand(1..20)
    team2_init = team2_dex + rand(1..20)
    
    first_team = team1_init >= team2_init ? team1 : team2
    
    # 선공 팀 내에서 민첩 순 정렬
    sorted_team = first_team.sort_by do |p|
      user = @sheet_manager.find_user(p)
      -(user["민첩성"] || user[:dexterity] || 10).to_i
    end
    
    turn_order = sorted_team + (first_team == team1 ? team2 : team1).sort_by do |p|
      user = @sheet_manager.find_user(p)
      -(user["민첩성"] || user[:dexterity] || 10).to_i
    end
    
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
    BattleState.update(battle_id, state)
    
    # 참가자 태그
    tags = participants.map { |p| "@#{p}" }.join(" ")
    message = "#{tags}\n\n"
    message += "2:2 전투 시작!\n\n"
    message += "팀1: #{team1.join(', ')}\n"
    message += "팀2: #{team2.join(', ')}\n\n"
    message += "턴 순서: #{turn_order.join(' → ')}\n\n"
    message += show_all_hp(state)
    message += "\n\n@#{turn_order.first}\n"
    message += "[공격/@타겟] [방어/@아군] [반격] [물약사용/크기/@아군]"
    
    reply_to_status(reply_status, message, visibility)
  end

  # 4:4 전투 시작
  def start_4v4_battle(team1, team2, reply_status)
    participants = team1 + team2
    
    team1_dex = team1.sum do |p|
      user = @sheet_manager.find_user(p)
      (user["민첩성"] || user[:dexterity] || 10).to_i
    end
    
    team2_dex = team2.sum do |p|
      user = @sheet_manager.find_user(p)
      (user["민첩성"] || user[:dexterity] || 10).to_i
    end
    
    team1_init = team1_dex + rand(1..20)
    team2_init = team2_dex + rand(1..20)
    
    first_team = team1_init >= team2_init ? team1 : team2
    
    sorted_team = first_team.sort_by do |p|
      user = @sheet_manager.find_user(p)
      -(user["민첩성"] || user[:dexterity] || 10).to_i
    end
    
    turn_order = sorted_team + (first_team == team1 ? team2 : team1).sort_by do |p|
      user = @sheet_manager.find_user(p)
      -(user["민첩성"] || user[:dexterity] || 10).to_i
    end
    
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
    BattleState.update(battle_id, state)
    
    # 참가자 태그
    tags = participants.map { |p| "@#{p}" }.join(" ")
    message = "#{tags}\n\n"
    message += "4:4 전투 시작!\n\n"
    message += "팀1: #{team1.join(', ')}\n"
    message += "팀2: #{team2.join(', ')}\n\n"
    message += "턴 순서: #{turn_order.join(' → ')}\n\n"
    message += show_all_hp(state)
    message += "\n\n@#{turn_order.first}\n"
    message += "[공격/@타겟] [방어/@아군] [반격] [물약사용/크기/@아군]"
    
    reply_to_status(reply_status, message, visibility)
  end

  # 1:1 액션 처리
  def handle_battle_action(user_id, action_type, battle_id)
    state = BattleState.get(battle_id)
    return unless state
    
    handle_pvp_action(user_id, action_type, battle_id, state)
  end

  # 팀전 액션 처리
  def handle_multi_action(user_id, action_type, target_id, battle_id, state)
    user = @sheet_manager.find_user(user_id)
    user_name = user["이름"] || user_id
    
    # 참가자 태그
    tags = state[:participants].map { |p| "@#{p}" }.join(" ")
    
    case action_type
    when :attack
      target = @sheet_manager.find_user(target_id)
      
      # 같은 팀 공격 방지
      user_team = state[:teams][:team1].include?(user_id) ? :team1 : :team2
      target_team = state[:teams][:team1].include?(target_id) ? :team1 : :team2
      
      if user_team == target_team
        message = "#{tags}\n\n"
        message += "#{user_name}님, 아군을 공격할 수 없습니다!"
        reply_to_state(state, message)
        return
      end
      
      result = execute_attack(user, user_id, target, target_id, state, battle_id)
      
      message = "#{tags}\n\n"
      message += "#{user_name}의 공격 → #{target["이름"] || target_id}\n"
      message += "공격: #{result[:atk]} + D20: #{result[:atk_roll]} = #{result[:atk_total]}\n"
      message += "방어: #{result[:def]} + D20: #{result[:def_roll]} = #{result[:def_total]}\n\n"
      
      if result[:damage] > 0
        message += "#{result[:damage]} 피해!\n"
        message += "남은 HP: #{result[:new_hp]}\n"
      else
        message += "공격 실패!\n"
      end
      
      message += show_all_hp(state)
      
      if result[:new_hp] <= 0
        # 팀 전멸 확인
        target_team = state[:teams][:team1].include?(target_id) ? :team1 : :team2
        alive = state[:teams][target_team].any? do |p|
          member = @sheet_manager.find_user(p)
          (member["HP"] || 0).to_i > 0
        end
        
        unless alive
          winner_team = target_team == :team1 ? :team2 : :team1
          message += "\n\n#{winner_team == :team1 ? '팀1' : '팀2'} 승리!"
          reply_to_state(state, message)
          BattleState.clear(battle_id)
          return
        end
      end
      
      # 다음 턴
      next_turn_multi(state, battle_id)
      current_user = @sheet_manager.find_user(state[:current_turn])
      
      message += "\n\n@#{state[:current_turn]}\n"
      message += "[공격/@타겟] [방어/@아군] [반격] [물약사용/크기/@아군]"
      
      reply_to_state(state, message)
      
    when :defend
      state[:guarded][user_id] = true
      BattleState.update(battle_id, state)
      
      next_turn_multi(state, battle_id)
      current_user = @sheet_manager.find_user(state[:current_turn])
      
      message = "#{tags}\n\n"
      message += "#{user_name}이(가) 방어 태세!\n\n"
      message += "@#{state[:current_turn]}\n"
      message += "[공격/@타겟] [방어/@아군] [반격] [물약사용/크기/@아군]"
      
      reply_to_state(state, message)
      
    when :defend_target
      target = @sheet_manager.find_user(target_id)
      
      # 같은 팀만 방어 가능
      user_team = state[:teams][:team1].include?(user_id) ? :team1 : :team2
      target_team = state[:teams][:team1].include?(target_id) ? :team1 : :team2
      
      if user_team != target_team
        message = "#{tags}\n\n"
        message += "#{user_name}님, 아군만 방어할 수 있습니다!"
        reply_to_state(state, message)
        return
      end
      
      state[:guarded][target_id] = true
      BattleState.update(battle_id, state)
      
      next_turn_multi(state, battle_id)
      current_user = @sheet_manager.find_user(state[:current_turn])
      
      message = "#{tags}\n\n"
      message += "#{user_name}이(가) #{target["이름"] || target_id}을(를) 방어!\n\n"
      message += "@#{state[:current_turn]}\n"
      message += "[공격/@타겟] [방어/@아군] [반격] [물약사용/크기/@아군]"
      
      reply_to_state(state, message)
      
    when :counter
      result = execute_counter(user, user_id, state, battle_id)
      
      message = "#{tags}\n\n"
      if result[:triggered]
        message += "#{user_name}의 반격!\n"
        message += "반격 피해: #{result[:counter_damage]}\n"
        message += show_all_hp(state)
      else
        message += "#{user_name}이(가) 반격 태세를 취했습니다."
      end
      
      next_turn_multi(state, battle_id)
      current_user = @sheet_manager.find_user(state[:current_turn])
      
      message += "\n\n@#{state[:current_turn]}\n"
      message += "[공격/@타겟] [방어/@아군] [반격] [물약사용/크기/@아군]"
      
      reply_to_state(state, message)
    end
  end

  # 공격 실행
  def execute_attack(attacker, attacker_id, defender, defender_id, state, battle_id)
    atk = (attacker["공격"] || attacker[:attack] || 10).to_i
    def_stat = (defender["방어"] || defender[:defense] || 10).to_i
    luck = (attacker["행운"] || attacker[:luck] || 10).to_i
    
    atk_roll = rand(1..20)
    def_roll = rand(1..20)
    
    # 치명타 (행운 기반)
    crit_chance = [luck * 2, 50].min
    is_crit = rand(1..100) <= crit_chance
    
    atk_total = atk + atk_roll
    atk_total = (atk_total * 1.5).to_i if is_crit
    
    # 방어 태세 확인
    if state[:guarded][defender_id]
      def_roll += 5
      state[:guarded].delete(defender_id)
    end
    
    def_total = def_stat + def_roll
    
    damage = [atk_total - def_total, 0].max
    
    current_hp = (defender["HP"] || 100).to_i
    new_hp = [current_hp - damage, 0].max
    
    @sheet_manager.update_user(defender_id, { "HP" => new_hp })
    
    BattleState.update(battle_id, state)
    
    {
      atk: atk,
      atk_roll: atk_roll,
      atk_total: atk_total,
      def: def_stat,
      def_roll: def_roll,
      def_total: def_total,
      damage: damage,
      new_hp: new_hp,
      is_crit: is_crit
    }
  end

  # 반격 실행
  def execute_counter(user, user_id, state, battle_id)
    state[:counter_stance] ||= {}
    state[:counter_stance][user_id] = true
    BattleState.update(battle_id, state)
    
    {
      triggered: false,
      counter_damage: 0
    }
  end

  private

  # 최대 HP 계산
  def calculate_max_hp(user)
    vitality = (user["체력"] || user[:vitality] || 10).to_i
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

  # PvP 액션 처리
  def handle_pvp_action(user_id, action_type, battle_id, state)
    opponent_id = state[:participants].find { |p| p != user_id }
    
    user = @sheet_manager.find_user(user_id)
    opponent = @sheet_manager.find_user(opponent_id)
    
    user_name = user["이름"] || user_id
    opponent_name = opponent["이름"] || opponent_id
    
    # 참가자 태그
    tags = "@#{user_id} @#{opponent_id}\n\n"

    case action_type
    when :attack
      result = execute_attack(user, user_id, opponent, opponent_id, state, battle_id)
      
      message = "#{tags}"
      message += "#{user_name}의 공격\n"
      message += "공격: #{result[:atk]} + D20: #{result[:atk_roll]} = #{result[:atk_total]}\n\n"
      message += "#{opponent_name}의 방어\n"
      message += "방어: #{result[:def]} + D20: #{result[:def_roll]} = #{result[:def_total]}\n\n"
      
      if result[:damage] > 0
        message += "#{opponent_name}에게 #{result[:damage]} 피해\n"
        message += "남은 HP: #{result[:new_hp]}\n"
      else
        message += "#{opponent_name}이(가) 공격을 막았습니다!\n"
      end
      
      message += show_all_hp(state)

      if result[:new_hp] <= 0
        message += "\n\n#{user_name} 승리!"
        reply_to_state(state, message)
        BattleState.clear(battle_id)
        return
      end

      state[:current_turn] = opponent_id
      state[:round] += 1
      BattleState.update(battle_id, state)

      message += "\n\n@#{opponent_id}\n"
      message += "[공격] [방어] [반격] [물약사용/크기]"

      reply_to_state(state, message)

    when :defend
      state[:guarded][user_id] = true
      BattleState.update(battle_id, state)
      
      message = "#{tags}"
      message += "#{user_name}이(가) 방어 태세를 취했습니다.\n\n"
      message += "@#{opponent_id}\n"
      message += "[공격] [방어] [반격] [물약사용/크기]"
      
      state[:current_turn] = opponent_id
      state[:round] += 1
      BattleState.update(battle_id, state)

      reply_to_state(state, message)

    when :counter
      result = execute_counter(user, user_id, state, battle_id)
      
      message = "#{tags}"
      message += "#{user_name}이(가) 반격 태세를 취했습니다.\n\n"
      message += "@#{opponent_id}\n"
      message += "[공격] [방어] [반격] [물약사용/크기]"
      
      state[:current_turn] = opponent_id
      state[:round] += 1
      BattleState.update(battle_id, state)

      reply_to_state(state, message)
    end
  end

  # 팀전 다음 턴
  def next_turn_multi(state, battle_id)
    turn_order = state[:turn_order]
    current_index = turn_order.index(state[:current_turn])
    
    # 다음 살아있는 참가자 찾기
    next_index = (current_index + 1) % turn_order.length
    tried = 0
    
    while tried < turn_order.length
      next_user_id = turn_order[next_index]
      next_user = @sheet_manager.find_user(next_user_id)
      
      if (next_user["HP"] || 0).to_i > 0
        state[:current_turn] = next_user_id
        state[:round] += 1 if next_index == 0
        BattleState.update(battle_id, state)
        return
      end
      
      next_index = (next_index + 1) % turn_order.length
      tried += 1
    end
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
      # fallback: 해시로 생성
      status = {
        'id' => state[:thread_ts],
        'visibility' => visibility
      }
      @client.reply(status, message, visibility: visibility)
    end
  end
end
