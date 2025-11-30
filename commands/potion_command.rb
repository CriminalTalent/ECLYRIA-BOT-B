require_relative '../core/battle_state'

class PotionCommand
  POTION_TYPES = {
    "소형물약" => 10,
    "중형물약" => 30,
    "대형물약" => 50
  }

  def initialize(mastodon_client, sheet_manager)
    @mastodon_client = mastodon_client
    @sheet_manager = sheet_manager
  end

  def use_potion(user_id, reply_status, potion_type = nil)
    use_potion_internal(user_id, user_id, reply_status, potion_type)
  end

  def use_potion_for_target(user_id, reply_status, potion_type, target_id)
    target_id = target_id.gsub('@', '').strip
    use_potion_internal(user_id, target_id, reply_status, potion_type)
  end

  private

  def use_potion_internal(user_id, target_id, reply_status, potion_type)
    puts "[디버그] use_potion_internal 시작: user_id=#{user_id}, target_id=#{target_id}, potion_type=#{potion_type}"
    
    state = BattleState.get
    in_battle = state && !state.empty?
    
    # 전투 중이면 턴 확인
    if in_battle && state[:current_turn].to_s != user_id.to_s
      @mastodon_client.reply(reply_status, "당신의 턴이 아닙니다.")
      return
    end

    # 스탯 시트에서 전투 정보 조회
    user = @sheet_manager.find_user(user_id)
    target = @sheet_manager.find_user(target_id)
    
    puts "[디버그] user 찾기 결과: #{user ? '성공' : '실패'}"
    puts "[디버그] target 찾기 결과: #{target ? '성공' : '실패'}"

    unless user
      @mastodon_client.reply(reply_status, "사용자 정보를 찾을 수 없습니다.")
      return
    end

    unless target
      @mastodon_client.reply(reply_status, "대상을 찾을 수 없습니다.")
      return
    end

    # 전투 중이면 참가자 확인
    if in_battle && !state[:participants].include?(target_id)
      @mastodon_client.reply(reply_status, "전투 참가자가 아닙니다.")
      return
    end

    # 사용자 시트에서 아이템 정보 조회
    user_data = @sheet_manager.find_user_items(user_id)
    
    puts "[디버그] find_user_items 결과: #{user_data ? '성공' : '실패'}"
    puts "[디버그] user_data 내용: #{user_data.inspect}" if user_data
    
    unless user_data
      user_name = user["이름"] || user_id
      if in_battle
        if state[:type] == "2v2"
          handle_failed_potion_2v2(user_id, user_name, state)
        else
          handle_failed_potion_1v1(user_id, user_name, state)
        end
      else
        @mastodon_client.reply(reply_status, "#{user_name}은(는) 물약이 없습니다.")
      end
      return
    end

    items = (user_data["아이템"] || "").strip
    
    puts "[디버그] 아이템 목록: #{items.inspect}"

    # 공백 제거하고 비교
    available_potions = []
    items_clean = items.gsub(/\s+/, "")
    POTION_TYPES.keys.each do |potion|
      potion_clean = potion.gsub(/\s+/, "")
      available_potions << potion if items_clean.include?(potion_clean)
    end

    if available_potions.empty?
      user_name = user["이름"] || user_id

      if in_battle
        if state[:type] == "2v2"
          handle_failed_potion_2v2(user_id, user_name, state)
        else
          handle_failed_potion_1v1(user_id, user_name, state)
        end
      else
        @mastodon_client.reply(reply_status, "#{user_name}은(는) 물약이 없습니다.")
      end
      return
    end

    # 물약 목록 표시
    if potion_type.nil?
      user_name = user["이름"] || user_id
      target_name = target["이름"] || target_id
      message = "#{user_name}의 물약 목록:\n"
      message += "━━━━━━━━━━━━━━━━━━\n"
      available_potions.each do |potion|
        heal = POTION_TYPES[potion]
        # "소형물약" → "소형 물약"
        potion_display = potion.gsub('물약', ' 물약').strip
        message += "• #{potion_display} (회복: #{heal})\n"
      end
      message += "━━━━━━━━━━━━━━━━━━\n"
      message += "사용법:\n"
      if user_id == target_id
        available_potions.each do |potion|
          # "소형물약" → "소형"
          potion_type_key = potion.gsub('물약', '')
          # 표시용: "소형 물약"
          potion_display = "#{potion_type_key} 물약"
          message += "[물약/#{potion_type_key}] - #{potion_display} 사용\n"
        end
        message = message.chomp
      else
        available_potions.each do |potion|
          potion_type_key = potion.gsub('물약', '')
          potion_display = "#{potion_type_key} 물약"
          message += "[물약/#{potion_type_key}/@#{target_id}] - #{target_name}에게 #{potion_display}\n"
        end
        message = message.chomp
      end

      if in_battle
        reply_to_battle(message, state)
      else
        @mastodon_client.reply(reply_status, message)
      end
      return
    end

    # 물약 찾기
    potion_found = nil
    case potion_type
    when /소형/i
      potion_found = "소형물약" if items_clean.include?("소형물약")
    when /중형/i
      potion_found = "중형물약" if items_clean.include?("중형물약")
    when /대형/i
      potion_found = "대형물약" if items_clean.include?("대형물약")
    end

    unless potion_found
      user_name = user["이름"] || user_id
      message = "#{user_name}은(는) 해당 종류의 물약이 없습니다.\n"
      message += "다시 [물약]으로 목록을 확인하세요."
      
      if in_battle
        reply_to_battle(message, state)
      else
        @mastodon_client.reply(reply_status, message)
      end
      return
    end

    # 물약 사용
    heal_amount = POTION_TYPES[potion_found]
    current_hp = (target["HP"] || 100).to_i
    new_hp = [current_hp + heal_amount, 100].min
    actual_heal = new_hp - current_hp

    # 스탯 시트 HP 업데이트
    @sheet_manager.update_user(target_id, { hp: new_hp })
    
    # 사용자 시트 아이템 업데이트
    new_items = items.sub(potion_found, "").gsub(/,+/, ",").gsub(/^,|,$/, "").strip
    @sheet_manager.update_user_items(user_id, { items: new_items })

    user_name = user["이름"] || user_id
    target_name = target["이름"] || target_id
    potion_display = potion_found.gsub('물약', ' 물약').strip

    if in_battle
      # 전투 중 물약 사용
      if state[:type] == "2v2"
        if user_id == target_id
          message = "#{user_name}이(가) #{potion_display}을 사용했습니다.\n"
        else
          message = "#{user_name}이(가) #{target_name}에게 #{potion_display}을 사용했습니다.\n"
        end
        message += "회복: #{actual_heal} (#{current_hp} → #{new_hp})\n"
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
          message += "[공격/@타겟] [방어/@타겟] [반격] [물약사용] [도주]"

          reply_to_battle(message, state)
        end
      else
        # 1v1 또는 허수아비
        if user_id == target_id
          message = "#{user_name}이(가) #{potion_display}을 사용했습니다.\n"
        else
          message = "#{user_name}이(가) #{target_name}에게 #{potion_display}을 사용했습니다.\n"
        end
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
    else
      # 평상시 물약 사용
      if user_id == target_id
        message = "#{user_name}이(가) #{potion_display}을 사용했습니다.\n"
      else
        message = "#{user_name}이(가) #{target_name}에게 #{potion_display}을 사용했습니다.\n"
      end
      message += "회복: #{actual_heal} (#{current_hp} → #{new_hp})"

      @mastodon_client.reply(reply_status, message)
    end
  end

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
      message += "[공격/@타겟] [방어/@타겟] [반격] [물약사용] [도주]"

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
