# core/battle_engine.rb
# Mastodon 기반 전투 엔진 (1:1, 2:2, 4:4 지원)

require_relative '../state/battle_state'
require_relative 'sheet_manager'
require 'securerandom'

class BattleEngine
  def initialize(mastodon_client)
    @client = mastodon_client
    @sheet_manager = SheetManager.new
  end

  # 1:1 전투 시작
  def start_battle(user_id, opponent_id, reply_status)
    battle_id = "battle_#{user_id}_#{opponent_id}_#{SecureRandom.hex(4)}"
    
    user = @sheet_manager.find_user(user_id)
    opponent = @sheet_manager.find_user(opponent_id)

    unless user && opponent
      @client.reply(reply_status, "전투 참가자를 찾을 수 없습니다.")
      return
    end

    user_name = user["이름"] || user_id
    opponent_name = opponent["이름"] || opponent_id

    state = {
      type: "pvp",
      participants: [user_id, opponent_id],
      current_turn: user_id,
      round: 1,
      guarded: {},
      counter: {},
      reply_status: reply_status
    }

    BattleState.update(battle_id, state)

    message = "⚔️ 전투 시작!\n"
    message += "#{user_name} vs #{opponent_name}\n"
    message += "━━━━━━━━━━━━━━━━━━\n"
    message += show_all_hp(state)
    message += "\n━━━━━━━━━━━━━━━━━━\n\n"
    message += "#{user_name}의 차례\n"
    message += "[공격] [방어] [반격] [물약사용/크기]"

    response = @client.reply(reply_status, message)
    
    if response && response[:id]
      state[:thread_status] = response
      BattleState.update(battle_id, state)
    end

    battle_id
  end

  # 2:2 전투 시작
  def start_2v2_battle(team1_users, team2_users, reply_status)
    battle_id = "2v2_#{SecureRandom.hex(6)}"
    
    all_users = team1_users + team2_users
    all_user_data = all_users.map { |uid| @sheet_manager.find_user(uid) }
    
    if all_user_data.any?(&:nil?)
      @client.reply(reply_status, "전투 참가자 중 일부를 찾을 수 없습니다.")
      return
    end

    # 팀별 민첩성 합계 계산
    team1_agility = team1_users.sum do |uid|
      user = @sheet_manager.find_user(uid)
      (user["민첩성"] || user[:agility] || 10).to_i
    end
    
    team2_agility = team2_users.sum do |uid|
      user = @sheet_manager.find_user(uid)
      (user["민첩성"] || user[:agility] || 10).to_i
    end
    
    # D20 굴리기
    team1_roll = rand(1..20)
    team2_roll = rand(1..20)
    
    team1_total = team1_agility + team1_roll
    team2_total = team2_agility + team2_roll
    
    # 선공 팀 결정
    first_team = team1_total >= team2_total ? :team1 : :team2
    second_team = first_team == :team1 ? :team2 : :team1
    
    # 각 팀 내부에서 민첩성 순으로 정렬
    team1_sorted = team1_users.sort_by do |uid|
      user = @sheet_manager.find_user(uid)
      -(user["민첩성"] || user[:agility] || 10).to_i
    end
    
    team2_sorted = team2_users.sort_by do |uid|
      user = @sheet_manager.find_user(uid)
      -(user["민첩성"] || user[:agility] || 10).to_i
    end
    
    # 턴 순서: 선공팀 전원 → 후공팀 전원
    turn_order = if first_team == :team1
                   team1_sorted + team2_sorted
                 else
                   team2_sorted + team1_sorted
                 end

    state = {
      type: "2v2",
      participants: all_users,
      teams: {
        team1: team1_users,
        team2: team2_users
      },
      turn_order: turn_order,
      turn_index: 0,
      current_turn: turn_order[0],
      round: 1,
      actions_queue: [],
      guarded: {},
      counter: {},
      protected_by: {},
      reply_status: reply_status
    }

    BattleState.update(battle_id, state)

    team1_names = team1_users.map { |uid| (@sheet_manager.find_user(uid)["이름"] || uid) }.join(", ")
    team2_names = team2_users.map { |uid| (@sheet_manager.find_user(uid)["이름"] || uid) }.join(", ")
    
    first_player = @sheet_manager.find_user(turn_order[0])
    first_player_name = first_player["이름"] || turn_order[0]

    message = "⚔️ 2:2 전투 시작!\n"
    message += "팀1: #{team1_names}\n"
    message += "팀2: #{team2_names}\n\n"
    message += "선공 판정\n"
    message += "팀1: 민첩성 #{team1_agility} + D20: #{team1_roll} = #{team1_total}\n"
    message += "팀2: 민첩성 #{team2_agility} + D20: #{team2_roll} = #{team2_total}\n"
    message += "#{first_team == :team1 ? '팀1' : '팀2'} 선공!\n"
    message += "━━━━━━━━━━━━━━━━━━\n"
    message += show_all_hp(state)
    message += "\n━━━━━━━━━━━━━━━━━━\n\n"
    message += "라운드 1 시작\n"
    message += "#{first_player_name}의 차례\n"
    message += "[공격/@타겟] [방어] [방어/@아군] [반격] [물약/크기/@아군]"

    response = @client.reply(reply_status, message)
    
    if response && response[:id]
      state[:thread_status] = response
      BattleState.update(battle_id, state)
    end

    battle_id
  end

  # 4:4 전투 시작
  def start_4v4_battle(team1_users, team2_users, reply_status)
    battle_id = "4v4_#{SecureRandom.hex(6)}"
    
    all_users = team1_users + team2_users
    all_user_data = all_users.map { |uid| @sheet_manager.find_user(uid) }
    
    if all_user_data.any?(&:nil?)
      @client.reply(reply_status, "전투 참가자 중 일부를 찾을 수 없습니다.")
      return
    end

    # 팀별 민첩성 합계 계산
    team1_agility = team1_users.sum do |uid|
      user = @sheet_manager.find_user(uid)
      (user["민첩성"] || user[:agility] || 10).to_i
    end
    
    team2_agility = team2_users.sum do |uid|
      user = @sheet_manager.find_user(uid)
      (user["민첩성"] || user[:agility] || 10).to_i
    end
    
    # D20 굴리기
    team1_roll = rand(1..20)
    team2_roll = rand(1..20)
    
    team1_total = team1_agility + team1_roll
    team2_total = team2_agility + team2_roll
    
    # 선공 팀 결정
    first_team = team1_total >= team2_total ? :team1 : :team2
    second_team = first_team == :team1 ? :team2 : :team1
    
    # 각 팀 내부에서 민첩성 순으로 정렬
    team1_sorted = team1_users.sort_by do |uid|
      user = @sheet_manager.find_user(uid)
      -(user["민첩성"] || user[:agility] || 10).to_i
    end
    
    team2_sorted = team2_users.sort_by do |uid|
      user = @sheet_manager.find_user(uid)
      -(user["민첩성"] || user[:agility] || 10).to_i
    end
    
    # 턴 순서: 선공팀 전원 → 후공팀 전원
    turn_order = if first_team == :team1
                   team1_sorted + team2_sorted
                 else
                   team2_sorted + team1_sorted
                 end

    state = {
      type: "4v4",
      participants: all_users,
      teams: {
        team1: team1_users,
        team2: team2_users
      },
      turn_order: turn_order,
      turn_index: 0,
      current_turn: turn_order[0],
      round: 1,
      actions_queue: [],
      guarded: {},
      counter: {},
      protected_by: {},
      reply_status: reply_status
    }

    BattleState.update(battle_id, state)

    team1_names = team1_users.map { |uid| (@sheet_manager.find_user(uid)["이름"] || uid) }.join(", ")
    team2_names = team2_users.map { |uid| (@sheet_manager.find_user(uid)["이름"] || uid) }.join(", ")
    
    first_player = @sheet_manager.find_user(turn_order[0])
    first_player_name = first_player["이름"] || turn_order[0]

    message = "⚔️ 4:4 전투 시작!\n"
    message += "팀1: #{team1_names}\n"
    message += "팀2: #{team2_names}\n\n"
    message += "선공 판정\n"
    message += "팀1: 민첩성 #{team1_agility} + D20: #{team1_roll} = #{team1_total}\n"
    message += "팀2: 민첩성 #{team2_agility} + D20: #{team2_roll} = #{team2_total}\n"
    message += "#{first_team == :team1 ? '팀1' : '팀2'} 선공!\n"
    message += "━━━━━━━━━━━━━━━━━━\n"
    message += show_all_hp(state)
    message += "\n━━━━━━━━━━━━━━━━━━\n\n"
    message += "라운드 1 시작\n"
    message += "#{first_player_name}의 차례\n"
    message += "[공격/@타겟] [방어] [방어/@아군] [반격] [물약/크기/@아군]"

    response = @client.reply(reply_status, message)
    
    if response && response[:id]
      state[:thread_status] = response
      BattleState.update(battle_id, state)
    end

    battle_id
  end

  # 전투 액션 처리 (1:1용)
  def handle_battle_action(user_id, action_type, battle_id)
    state = BattleState.get(battle_id)
    return unless state

    unless state[:participants].include?(user_id)
      return
    end

    if state[:current_turn] != user_id
      reply_to_thread("당신의 차례가 아닙니다.", state)
      return
    end

    handle_pvp_action(user_id, action_type, battle_id, state)
  end

  # 2:2/4:4 전투 액션 처리
  def handle_multi_action(user_id, action_type, target_id, battle_id, state)
    if action_type == :attack
      unless target_id
        reply_to_thread("팀 전투에서는 [공격/@타겟] 형식으로 타겟을 지정해야 합니다.", state)
        return
      end
      
      unless state[:participants].include?(target_id)
        reply_to_thread("잘못된 타겟입니다.", state)
        return
      end
      
      my_team = state[:teams][:team1].include?(user_id) ? :team1 : :team2
      if state[:teams][my_team].include?(target_id)
        reply_to_thread("아군을 공격할 수 없습니다!", state)
        return
      end
    end
    
    # 대리 방어 처리
    if action_type == :defend_target
      unless target_id
        reply_to_thread("[방어/@아군] 형식으로 보호할 아군을 지정해야 합니다.", state)
        return
      end
      
      unless state[:participants].include?(target_id)
        reply_to_thread("잘못된 타겟입니다.", state)
        return
      end
      
      my_team = state[:teams][:team1].include?(user_id) ? :team1 : :team2
      unless state[:teams][my_team].include?(target_id)
        reply_to_thread("같은 팀원만 방어할 수 있습니다!", state)
        return
      end
      
      # protected_by 상태에 기록
      state[:protected_by] ||= {}
      state[:protected_by][target_id] = user_id
    end

    state[:actions_queue] ||= []
    state[:actions_queue] << {
      user_id: user_id,
      action: action_type,
      target: target_id
    }

    user = @sheet_manager.find_user(user_id)
    user_name = user["이름"] || user_id
    
    action_text = case action_type
                  when :attack
                    target_name = (@sheet_manager.find_user(target_id) || {})["이름"] || target_id
                    "#{user_name}이(가) #{target_name}을(를) 공격 준비"
                  when :defend
                    "#{user_name}이(가) 방어 태세"
                  when :defend_target
                    target_name = (@sheet_manager.find_user(target_id) || {})["이름"] || target_id
                    "#{user_name}이(가) #{target_name}을(를) 보호 준비"
                  when :counter
                    "#{user_name}이(가) 반격 태세"
                  end
    
    message = "#{action_text}\n"
    message += "━━━━━━━━━━━━━━━━━━\n"

    state[:turn_index] += 1
    BattleState.update(battle_id, state)
    
    # 2:2는 4명, 4:4는 8명
    total_players = state[:type] == "2v2" ? 4 : 8
    
    if state[:turn_index] >= total_players
      process_multi_round(battle_id, state, message)
    else
      state[:current_turn] = state[:turn_order][state[:turn_index]]
      BattleState.update(battle_id, state)
      
      next_player = @sheet_manager.find_user(state[:current_turn])
      next_player_name = next_player["이름"] || state[:current_turn]
      
      message += "#{next_player_name}의 차례\n"
      message += "[공격/@타겟] [방어] [방어/@아군] [반격] [물약/크기/@아군]"
      
      reply_to_thread(message, state)
    end
  end

  # 2:2/4:4 라운드 처리
  def process_multi_round(battle_id, state, prefix_message)
    message = prefix_message
    message += "\n라운드 #{state[:round]} 결과\n"
    message += "━━━━━━━━━━━━━━━━━━\n\n"

    # 방어 및 보호 상태 설정
    state[:actions_queue].each do |action|
      if action[:action] == :defend
        state[:guarded] ||= {}
        state[:guarded][action[:user_id]] = true
      elsif action[:action] == :defend_target
        state[:protected_by] ||= {}
        state[:protected_by][action[:target]] = action[:user_id]
      elsif action[:action] == :counter
        state[:counter] ||= {}
        state[:counter][action[:user_id]] = true
      end
    end

    # 공격 처리
    state[:actions_queue].each do |action|
      next unless action[:action] == :attack
      
      attacker = @sheet_manager.find_user(action[:user_id])
      defender = @sheet_manager.find_user(action[:target])
      
      next unless attacker && defender
      
      result = calculate_attack_result(attacker, action[:user_id], defender, action[:target], state, battle_id)
      message += result[:message] + "\n"
      
      if result[:damage] > 0
        new_hp = [(defender["HP"] || 0).to_i - result[:damage], 0].max
        @sheet_manager.update_user(action[:target], { hp: new_hp })
      end
      
      if result[:counter_damage] > 0
        attacker_new_hp = [(attacker["HP"] || 0).to_i - result[:counter_damage], 0].max
        @sheet_manager.update_user(action[:user_id], { hp: attacker_new_hp })
      end
    end

    message += "\n"
    message += show_all_hp(state)

    team1_alive = state[:teams][:team1].count do |pid|
      u = @sheet_manager.find_user(pid)
      u && (u["HP"] || 0).to_i > 0
    end
    
    team2_alive = state[:teams][:team2].count do |pid|
      u = @sheet_manager.find_user(pid)
      u && (u["HP"] || 0).to_i > 0
    end

    if team1_alive == 0
      message += "\n\n팀2 승리!"
      reply_to_thread(message, state)
      BattleState.clear(battle_id)
      return
    elsif team2_alive == 0
      message += "\n\n팀1 승리!"
      reply_to_thread(message, state)
      BattleState.clear(battle_id)
      return
    end

    state[:round] += 1
    state[:turn_index] = 0
    state[:actions_queue] = []
    state[:guarded] = {}
    state[:counter] = {}
    state[:protected_by] = {}
    state[:current_turn] = state[:turn_order][0]
    BattleState.update(battle_id, state)

    first_player = @sheet_manager.find_user(state[:current_turn])
    first_player_name = first_player["이름"] || state[:current_turn]
    
    message += "\n\n라운드 #{state[:round]} 시작\n"
    message += "#{first_player_name}의 차례\n"
    message += "[공격/@타겟] [방어] [방어/@아군] [반격] [물약/크기/@아군]"

    reply_to_thread(message, state)
  end

  # 공격 결과 계산
  def calculate_attack_result(attacker, attacker_id, defender, defender_id, state, battle_id)
    attacker_name = attacker["이름"] || attacker_id
    defender_name = defender["이름"] || defender_id
    
    atk = (attacker["공격"] || 10).to_i
    atk_roll = rand(1..20)
    luck = (attacker["행운"] || 10).to_i
    
    crit_result = check_critical_hit(luck)
    atk_total = atk + atk_roll
    
    # 기본 방어자 스탯
    def_stat = (defender["방어"] || 10).to_i
    def_roll = rand(1..20)
    def_total = def_stat + def_roll
    
    # 방어 시스템 체크
    guard_text = ""
    
    # 1. 자신의 방어 태세 체크
    if state.dig(:guarded, defender_id)
      guard_roll = rand(1..20)
      guard_total = def_stat + guard_roll
      
      if guard_total >= atk_total
        damage = 0
        guard_text = " / 방어 성공! (#{guard_roll}+#{def_stat}=#{guard_total}) 피해 차단"
      else
        damage = atk_total - guard_total
        if crit_result[:is_crit]
          damage = (damage * 1.5).to_i
        end
        guard_text = " / 방어 실패 (#{guard_roll}+#{def_stat}=#{guard_total})"
      end
      
      state[:guarded].delete(defender_id)
      BattleState.update(battle_id, state)
    # 2. 아군의 대리 방어 체크
    elsif state[:protected_by] && state[:protected_by][defender_id]
      protector_id = state[:protected_by][defender_id]
      protector = @sheet_manager.find_user(protector_id)
      protector_name = protector["이름"] || protector_id
      
      # 보호자의 방어 스탯으로 판정
      protector_def = (protector["방어"] || 10).to_i
      guard_roll = rand(1..20)
      guard_total = protector_def + guard_roll
      
      if guard_total >= atk_total
        damage = 0
        guard_text = " / #{protector_name}의 방어! (#{guard_roll}+#{protector_def}=#{guard_total}) 피해 차단"
      else
        damage = atk_total - guard_total
        if crit_result[:is_crit]
          damage = (damage * 1.5).to_i
        end
        guard_text = " / #{protector_name}의 방어 (#{guard_roll}+#{protector_def}=#{guard_total})"
      end
      
      state[:protected_by].delete(defender_id)
      BattleState.update(battle_id, state)
    else
      # 일반 방어
      damage = [atk_total - def_total, 0].max
      
      if crit_result[:is_crit]
        damage = (damage * 1.5).to_i
      end
    end

    counter_damage = 0
    counter_text = ""
    if state.dig(:counter, defender_id) && damage > 0
      counter_damage = 5
      counter_text = " / 반격 5"
    end

    message = "#{attacker_name} → #{defender_name}: (#{atk_roll}+#{atk})"
    message += " [치명타!]" if crit_result[:is_crit]
    message += " vs (#{def_roll}+#{def_stat})"
    message += guard_text
    message += " = 데미지 #{damage}"
    message += counter_text
    
    current_hp = (defender["HP"] || 0).to_i
    new_hp = [current_hp - damage, 0].max
    message += " (#{defender_name} #{new_hp}/#{calculate_max_hp(defender)})"

    {
      message: message,
      damage: damage,
      counter_damage: counter_damage
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

  # 체력바 생성 (█ 사용, 10칸 기준)
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

  # PvP 액션 처리 (1:1)
  def handle_pvp_action(user_id, action_type, battle_id, state)
    opponent_id = state[:participants].find { |p| p != user_id }
    
    user = @sheet_manager.find_user(user_id)
    opponent = @sheet_manager.find_user(opponent_id)
    
    user_name = user["이름"] || user_id
    opponent_name = opponent["이름"] || opponent_id

    case action_type
    when :attack
      result = execute_attack(user, user_id, opponent, opponent_id, state, battle_id)
      
      message = "#{user_name}의 공격\n"
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
        reply_to_thread(message, state)
        BattleState.clear(battle_id)
        return
      end

      state[:current_turn] = opponent_id
      state[:round] += 1
      BattleState.update(battle_id, state)

      message += "\n\n"
      message += "#{opponent_name}의 차례\n"
      message += "[공격] [방어] [반격] [물약사용/크기]"

      reply_to_thread(message, state)

    when :defend
      state[:guarded][user_id] = true
      BattleState.update(battle_id, state)
      
      message = "#{user_name}이(가) 방어 태세를 취했습니다.\n\n"
      message += "#{opponent_name}의 차례\n"
      message += "[공격] [방어] [반격] [물약사용/크기]"
      
      state[:current_turn] = opponent_id
      BattleState.update(battle_id, state)
      
      reply_to_thread(message, state)

    when :counter
      state[:counter][user_id] = true
      BattleState.update(battle_id, state)
      
      message = "#{user_name}이(가) 반격 태세를 취했습니다.\n\n"
      message += "#{opponent_name}의 차례\n"
      message += "[공격] [방어] [반격] [물약사용/크기]"
      
      state[:current_turn] = opponent_id
      BattleState.update(battle_id, state)
      
      reply_to_thread(message, state)
    end
  end

  # 공격 실행 (1:1용)
  def execute_attack(attacker, attacker_id, defender, defender_id, state, battle_id)
    atk = (attacker["공격"] || 10).to_i
    atk_roll = rand(1..20)
    luck = (attacker["행운"] || 10).to_i
    
    crit_result = check_critical_hit(luck)
    atk_total = atk + atk_roll
    
    def_stat = (defender["방어"] || 10).to_i
    
    if state[:guarded] && state[:guarded][defender_id]
      guard_roll = rand(1..20)
      guard_total = def_stat + guard_roll
      
      if guard_total >= atk_total
        damage = 0
      else
        damage = atk_total - guard_total
        damage = (damage * 1.5).to_i if crit_result[:is_crit]
      end
      
      state[:guarded].delete(defender_id)
      BattleState.update(battle_id, state)
      
      def_roll = guard_roll
      def_total = guard_total
    else
      def_roll = rand(1..20)
      def_total = def_stat + def_roll
      
      damage = [atk_total - def_total, 0].max
      damage = (damage * 1.5).to_i if crit_result[:is_crit]
    end

    if state[:counter] && state[:counter][defender_id] && damage > 0
      counter_damage = 5
      attacker_hp = (attacker["HP"] || 0).to_i
      new_attacker_hp = [attacker_hp - counter_damage, 0].max
      @sheet_manager.update_user(attacker_id, { hp: new_attacker_hp })
      
      state[:counter].delete(defender_id)
      BattleState.update(battle_id, state)
    end

    current_hp = (defender["HP"] || 0).to_i
    new_hp = [current_hp - damage, 0].max
    @sheet_manager.update_user(defender_id, { hp: new_hp })

    {
      atk: atk,
      atk_roll: atk_roll,
      atk_total: atk_total,
      def: def_stat,
      def_roll: def_roll,
      def_total: def_total,
      damage: damage,
      new_hp: new_hp,
      is_crit: crit_result[:is_crit]
    }
  end

  # 치명타 판정
  def check_critical_hit(luck)
    crit_chance = [5 + (luck / 5), 95].min
    roll = rand(1..100)
    
    {
      is_crit: roll <= crit_chance,
      roll: roll,
      threshold: crit_chance
    }
  end

  # 스레드에 답글 (Mastodon)
  def reply_to_thread(message, state)
    return unless state[:thread_status]
    
    @client.reply(state[:thread_status], message)
  end
end
