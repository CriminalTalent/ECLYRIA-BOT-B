require_relative '../core/battle_state'

class PotionCommand
  # 물약 종류별 회복량 (고정값)
  POTION_TYPES = {
    "소형 물약" => 10,
    "중형 물약" => 30,
    "대형 물약" => 50,
    "물약" => 20        # 기본 물약
  }

  def initialize(mastodon_client, sheet_manager)
    @mastodon_client = mastodon_client
    @sheet_manager = sheet_manager
  end

  def use_potion(user_id, reply_status, potion_type = nil)
    state = BattleState.get
    unless state && !state.empty?
      @mastodon_client.reply(reply_status, "전투 중에만 물약을 사용할 수 있습니다.")
      return
    end

    unless state[:current_turn] == user_id
      @mastodon_client.reply(reply_status, "당신의 턴이 아닙니다.")
      return
    end

    user = @sheet_manager.find_user(user_id)
    unless user
      @mastodon_client.reply(reply_status, "사용자 정보를 찾을 수 없습니다.")
      return
    end

    items = user["아이템"] || user[:items] || ""
    
    unless items.include?("물약")
      user_name = user["이름"] || user[:name] || user_id
      
      if state[:type] == "2v2"
        # 2:2는 행동 큐에 실패 기록 후 넘김
        handle_failed_potion_2v2(user_id, user_name, state)
      else
        # 1:1은 즉시 처리
        handle_failed_potion_1v1(user_id, user_name, state)
      end
      return
    end
    
    available_potions = []
    POTION_TYPES.keys.each do |potion|
      available_potions << potion if items.include?(potion)
    end

    if available_potions.empty?
      user_name = user["이름"] || user[:name] || user_id
      
      if state[:type] == "2v2"
        handle_failed_potion_2v2(user_id, user_name, state)
      else
        handle_failed_potion_1v1(user_id, user_name, state)
      end
      return
    end

    if potion_type.nil?
      user_name = user["이름"] || user[:name] || user_id
      message = "#{user_name}의 물약 목록:\n"
      message += "━━━━━━━━━━━━━━━━━━\n"
      available_potions.each do |potion|
        heal = POTION_TYPES[potion]
        message += "• #{potion} (회복: #{heal})\n"
      end
      message += "━━━━━━━━━━━━━━━━━━\n"
      message += "사용법:\n"
      message += "[물약사용/소형] - 소형 물약 사용\n"
      message += "[물약사용/중형] - 중형 물약 사용\n"
      message += "[물약사용/대형] - 대형 물약 사용"
      
      reply_to_battle(message, state)
      return
    end

    potion_found = nil
    case potion_type
    when /소형/i
      potion_found = "소형 물약" if items.include?("소형 물약")
    when /중형/i
      potion_found = "중형 물약" if items.include?("중형 물약")
    when /대형/i
      potion_found = "대형 물약" if items.include?("대형 물약")
    when /기본|일반/i
      potion_found = "물약" if items.include?("물약")
    end

    unless potion_found
      user_name = user["이름"] || user[:name] || user_id
      message = "#{user_name}은(는) 해당 종류의 물약이 없습니다.\n"
      message += "다시 [물약사용]으로 목록을 확인하세요."
      reply_to_battle(message, state)
      return
    end

    heal_amount = POTION_TYPES[potion_found]
    current_hp = (user["HP"] || user[:hp] || 100).to_i
    new_hp = [current_hp + heal_amount, 100].min
    actual_heal = new_hp - current_hp

    @sheet_manager.update_user(user_id, { hp: new_hp })
    new_items = items.sub(potion_found, "").gsub(/,+/, ",").gsub(/^,|,$/, "").strip
    @sheet_manager.update_user(user_id, { items: new_items })

    user_name = user["이름"] || user[:name] || user_id
    
    if state[:type] == "2v2"
      # 2:2는 행동으로 기록 후 턴 진행
      message = "#{user_name}이(가) #{potion_found}을 사용했습니다.\n"
      message += "회복: #{actual_heal} (#{current_hp} → #{new_hp})\n"
      message += "━━━━━━━━━━━━━━━━━━\n"
      
      # 일단 물약은 즉시 처리 (행동 큐에 넣지 않음)
      state[:turn_index] += 1
      
      if state[:turn_index] >= 4
        # 라운드 종료
        require_relative '../core/battle_engine'
        engine = BattleEngine.new(@mastodon_client, @sheet_manager)
        engine.send(:process_2v2_round, state, message)
      else
        state[:current_turn] = state[:turn_order][state[:turn_index]]
        next_player = @sheet_manager.find_user(state[:current_turn])
        next_player_name = next_player["이름"] || state[:current_turn]
        
        message += "#{next_player_name}의 차례\n"
        message += "[공격/@타겟] [방어] [반격] [물약사용] [도주]"
        
        reply_to_battle(message, state)
      end
    else
      # 1:1/허수아비는 기존 로직
      message = "#{user_name}이(가) #{potion_found}을 사용했습니다.\n"
      message += "회복: #{actual_heal} (#{current_hp} → #{new_hp})\n"
      message += "━━━━━━━━━━━━━━━━━━\n"

      state[:current_turn] = state[:turn_order][(state[:turn_order].index(state[:current_turn]) + 1) % state[:turn_order].length]
      
      if state[:current_turn].to_s.include?("허수아비")
        reply_to_battle(message, state)
      else
        next_player = @sheet_manager.find_user(state[:current_turn])
        next_player_name = next_player ? (next_player["이름"] || state[:current_turn]) : state[:current_turn]
        
        message += "#{next_player_name}의 차례\n"
        message += "[공격] [방어] [반격] [물약사용] [도주]"
        
        reply_to_battle(message, state)
      end
    end
  end

  private

  def handle_failed_potion_2v2(user_id, user_name, state)
    message = "#{user_name}은(는) 물약이 없습니다!\n"
    message += "━━━━━━━━━━━━━━━━━━\n"
    
    state[:turn_index] += 1
    
    if state[:turn_index] >= 4
      require_relative '../core/battle_engine'
      engine = BattleEngine.new(@mastodon_client, @sheet_manager)
      engine.send(:process_2v2_round, state, message)
    else
      state[:current_turn] = state[:turn_order][state[:turn_index]]
      next_player = @sheet_manager.find_user(state[:current_turn])
      next_player_name = next_player["이름"] || state[:current_turn]
      
      message += "#{next_player_name}의 차례\n"
      message += "[공격/@타겟] [방어] [반격] [물약사용] [도주]"
      
      reply_to_battle(message, state)
    end
  end

  def handle_failed_potion_1v1(user_id, user_name, state)
    message = "#{user_name}은(는) 물약이 없습니다! 턴을 넘깁니다.\n"
    message += "━━━━━━━━━━━━━━━━━━\n"
    
    state[:current_turn] = state[:turn_order][(state[:turn_order].index(state[:current_turn]) + 1) % state[:turn_order].length]
    
    if state[:current_turn].to_s.include?("허수아비")
      reply_to_battle(message, state)
    else
      next_player = @sheet_manager.find_user(state[:current_turn])
      next_player_name = next_player ? (next_player["이름"] || state[:current_turn]) : state[:current_turn]
      
      message += "#{next_player_name}의 차례\n"
      message += "[공격] [방어] [반격] [물약사용] [도주]"
      
      reply_to_battle(message, state)
    end
  end

  def reply_to_battle(message, state)
    return unless state[:reply_status]
    participants = state[:participants].reject { |p| p.include?("허수아비") }
    @mastodon_client.reply_with_mentions(state[:reply_status], message, participants)
  end
end
