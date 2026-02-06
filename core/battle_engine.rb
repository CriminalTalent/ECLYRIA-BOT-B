  def reply_to_status(status, message, visibility = nil)
    use_visibility = visibility || get_visibility(status)
    if message.length <= 490
      @client.reply(status, message, visibility: use_visibility)
    else
      parts = split_message(message)
      previous_status = status
      parts.each do |part|
        previous_status = @client.reply(previous_status, part, visibility: use_visibility)
      end
    end
  end

  def split_message(message, max_length = 490)
    lines = message.split("\n")
    parts = []
    current = ""

    lines.each do |line|
      if current.length + line.length + 1 > max_length
        parts << current.strip
        current = ""
      end
      current += line + "\n"
    end

    parts << current.strip unless current.empty?
    parts
  end

  def show_all_hp(state)
    message = "━━━━━━━━━━━━━━━━━━\n"
    message += "현재 체력\n"
    state[:participants].each do |participant_id|
      participant = @sheet_manager.find_user(participant_id)
      next unless participant
      name = participant["이름"] || participant_id
      current_hp = (participant["HP"] || 0).to_i
      max_hp = 100 + ((participant["체력"] || 10).to_i * 10)
      hp_bar = generate_hp_bar(current_hp, max_hp)
      message += "#{name.ljust(12)} #{current_hp.to_s.rjust(3)}/#{max_hp} #{hp_bar}\n"
    end
    message += "━━━━━━━━━━━━━━━━━━"
    message
  end

  def generate_hp_bar(current_hp, max_hp)
    return "██████████" if current_hp >= max_hp
    return "░░░░░░░░░░" if current_hp <= 0 || max_hp <= 0
    hp_percent = (current_hp.to_f / max_hp.to_f * 100).round
    filled = (hp_percent / 10.0).floor
    empty = 10 - filled
    "█" * filled + "░" * empty
  end
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

    state[:actions] ||= {}
    state[:actions][user_id] = {
      type: action_type,
      target: target_id,
      potion_size: potion_size
    }

    user_name = get_user_name(user_id)

    # 다음 턴 결정
    turn_order = state[:turn_order] || state[:participants]
    current_index = turn_order.index(user_id)

    next_player = nil
    tried = 0

    while tried < turn_order.length
      next_index = (current_index + 1 + tried) % turn_order.length
      next_id = turn_order[next_index]

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
      BattleState.update(battle_id, state)
      process_round(state, battle_id)
    end
  end

  # 라운드 처리
  def process_round(state, battle_id)
    actions = state[:actions]
    messages = []
    tags = state[:participants].map { |p| "@#{p}" }.join(" ")

    # 1. 물약 사용
    potion_actions = actions.select { |_, a| a[:type] == :use_potion }
    potion_actions.each do |user_id, action|
      result = execute_potion(user_id, action[:potion_size], action[:target], state, battle_id)
      messages << result if result
    end

    # 2. 반격 설정
    counter_actions = actions.select { |_, a| a[:type] == :counter }
    counter_actions.each do |user_id, _|
      state[:counter_stance] ||= {}
      state[:counter_stance][user_id] = true
      messages << "#{get_user_name(user_id)}이(가) 반격 태세!"
    end

    # 3. 방어 및 대리 방어
    defend_actions = actions.select { |_, a| a[:type] == :defend }
    defend_actions.each do |user_id, action|
      target_id = action[:target]
      if target_id && target_id != user_id
        state[:protect] ||= {}
        state[:protect][target_id] = user_id
        messages << "#{get_user_name(user_id)}이(가) #{get_user_name(target_id)}을(를) 대리 방어!"
      else
        state[:guarded] ||= {}
        state[:guarded][user_id] = true
        messages << "#{get_user_name(user_id)}이(가) 방어 태세!"
      end
    end

    # 4. 공격 및 반격
    attack_actions = actions.select { |_, a| a[:type] == :attack }
    turn_order = state[:turn_order] || state[:participants]

    turn_order.each do |user_id|
      next unless attack_actions.key?(user_id)
      action = attack_actions[user_id]
      target_id = action[:target]

      attacker = @sheet_manager.find_user(user_id)
      defender = @sheet_manager.find_user(target_id)
      next if (attacker["HP"] || 0) <= 0 || (defender["HP"] || 0) <= 0

      # 같은 팀 공격 방지
      if %w[2v2 4v4].include?(state[:type])
        team1 = state[:teams][:team1]
        if team1.include?(user_id) == team1.include?(target_id)
          messages << "#{get_user_name(user_id)}의 공격 실패 (아군 공격 불가)"
          next
        end
      end

      # 대리 방어 처리
      actual_defender_id = target_id
      if state[:protect] && state[:protect][target_id]
        protector_id = state[:protect][target_id]
        protector = @sheet_manager.find_user(protector_id)
        if (protector["HP"] || 0) > 0
          actual_defender_id = protector_id
          messages << "#{get_user_name(protector_id)}이(가) #{get_user_name(target_id)}을(를) 대신 방어!"
        end
      end
      actual_defender = @sheet_manager.find_user(actual_defender_id)

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

      # 반격 처리
      if state[:counter_stance]&.[](actual_defender_id) && result[:damage] > 0
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
        state[:counter_stance].delete(actual_defender_id)
      end
    end

        # 라운드 결과 출력 및 다음 라운드 준비
    message = "#{tags}\n\n"
    message += "━━━━━━ 라운드 #{state[:round]} ━━━━━━\n\n"
    message += messages.join("\n\n")
    message += "\n\n" + show_all_hp(state)

    if check_battle_end(state, battle_id, message)
      return
    end

    # 다음 라운드 세팅
    state[:round] += 1
    state[:actions] = {}
    state[:guarded] = {}
    state[:counter_stance] = {}
    state[:protect] = {}

    # 첫 턴 플레이어 설정
    turn_order = state[:turn_order] || state[:participants]
    next_first = turn_order.find do |pid|
      user = @sheet_manager.find_user(pid)
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

  # 승패 판단
  def check_battle_end(state, battle_id, message)
    if state[:type] == "pvp"
      alive = state[:participants].select do |pid|
        (@sheet_manager.find_user(pid)["HP"] || 0).to_i > 0
      end

      if alive.length == 1
        message += "\n\n#{get_user_name(alive.first)} 승리!"
        reply_to_state(state, message)
        BattleState.clear(battle_id)
        return true
      elsif alive.empty?
        message += "\n\n무승부!"
        reply_to_state(state, message)
        BattleState.clear(battle_id)
        return true
      end
    else
      team1_alive = state[:teams][:team1].any? { |pid| (@sheet_manager.find_user(pid)["HP"] || 0) > 0 }
      team2_alive = state[:teams][:team2].any? { |pid| (@sheet_manager.find_user(pid)["HP"] || 0) > 0 }

      if !team1_alive && !team2_alive
        message += "\n\n무승부!"
        reply_to_state(state, message)
        BattleState.clear(battle_id)
        return true
      elsif !team1_alive
        message += "\n\n이그드라실 승리!"
        reply_to_state(state, message)
        BattleState.clear(battle_id)
        return true
      elsif !team2_alive
        message += "\n\n불사조 기사단 승리!"
        reply_to_state(state, message)
        BattleState.clear(battle_id)
        return true
      end
    end

    false
  end

  # 공격 처리
  def execute_attack(attacker, attacker_id, defender, defender_id, state, battle_id)
    atk = (attacker["공격"] || 10).to_i
    def_stat = (defender["방어"] || 10).to_i
    luck = (attacker["행운"] || 10).to_i

    atk_roll = rand(1..20)
    def_roll = rand(1..20)
    def_bonus = state[:guarded][defender_id] ? rand(1..20) : 0

    crit_chance = [(luck / 2.0 * 5).to_i, 50].min
    is_crit = rand(1..100) <= crit_chance

    atk_total = atk + atk_roll
    def_total = def_stat + def_roll + def_bonus

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

  # 반격 처리
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

  # 물약 사용
  def execute_potion(user_id, potion_size, target_id, state, battle_id)
    user = @sheet_manager.find_user(user_id)
    items_str = user["아이템"] || ""
    items = parse_items(items_str)

    potion_key = {
      "소형" => "소형물약",
      "중형" => "중형물약",
      "대형" => "대형물약"
    }[potion_size]

    return "#{get_user_name(user_id)}: 알 수 없는 물약" unless potion_key
    return "#{get_user_name(user_id)}: #{potion_key} 없음" unless items[potion_key].to_i > 0

    heal_amount = { "소형물약" => 10, "중형물약" => 30, "대형물약" => 50 }[potion_key]

    heal_target_id = target_id || user_id
    heal_target = @sheet_manager.find_user(heal_target_id)

    current_hp = (heal_target["HP"] || 0).to_i
    max_hp = calculate_max_hp(heal_target)
    new_hp = [current_hp + heal_amount, max_hp].min
    actual_heal = new_hp - current_hp

    @sheet_manager.update_user(heal_target_id, { "HP" => new_hp })

    items[potion_key] -= 1
    items.delete(potion_key) if items[potion_key] <= 0
    @sheet_manager.update_user(user_id, { "아이템" => items.map { |k, v| "#{k}:#{v}" }.join(", ") })

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
    items_str.split(',').each do |entry|
      k, v = entry.strip.split(':')
      items[k.strip] = v.strip.to_i if v
    end
    items
  end

  # 최대 HP 계산
  def calculate_max_hp(user)
    vitality = (user["체력"] || 10).to_i
    100 + vitality * 10
  end

  # 체력 바 출력
  def generate_hp_bar(current_hp, max_hp)
    return "██████████" if current_hp >= max_hp
    return "░░░░░░░░░░" if current_hp <= 0
    filled = (current_hp.to_f / max_hp * 10).floor
    empty = 10 - filled
    "█" * filled + "░" * empty
  end

  # 전체 체력 출력
  def show_all_hp(state)
    "━━━━━━━━━━━━━━━━━━\n현재 체력\n" +
    state[:participants].map do |pid|
      user = @sheet_manager.find_user(pid)
      next unless user
      name = user["이름"] || pid
      hp = (user["HP"] || 0).to_i
      max_hp = calculate_max_hp(user)
      bar = generate_hp_bar(hp, max_hp)
      "#{name}: #{hp}/#{max_hp} #{bar}"
    end.compact.join("\n") +
    "\n━━━━━━━━━━━━━━━━━━"
  end
end

