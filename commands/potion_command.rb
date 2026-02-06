require_relative '../core/battle_state'

class PotionCommand
  POTION_HEAL = {
    "소형" => 10,
    "중형" => 30,
    "대형" => 50
  }

  def initialize(mastodon_client, sheet_manager)
    @mastodon_client = mastodon_client
    @sheet_manager = sheet_manager
  end

  # 본인에게 물약 사용
  def use_potion(user_id, reply_status, potion_type = nil)
    unless potion_type
      @mastodon_client.reply(reply_status, "물약 크기를 지정하세요: [물약/소형] [물약/중형] [물약/대형]")
      return
    end

    user = @sheet_manager.find_user(user_id)
    unless user
      @mastodon_client.reply(reply_status, "등록되지 않은 사용자입니다.")
      return
    end

    user_name = user["이름"] || user_id
    heal_amount = POTION_HEAL[potion_type] || 10
    
    # 물약 소지 확인
    items = (user["아이템"] || "").split(',').map(&:strip)
    potion_key = "#{potion_type}물약"
    
    unless items.include?(potion_key)
      @mastodon_client.reply(reply_status, "#{user_name}은(는) #{potion_type}물약이 없습니다!")
      return
    end

    # 체력 계산
    vitality_stat = (user["체력"] || 0).to_i
    max_hp = 100 + (vitality_stat * 10)
    current_hp = (user["HP"] || 100).to_i
    new_hp = [current_hp + heal_amount, max_hp].min
    actual_heal = new_hp - current_hp

    # 물약 제거
    items.delete_at(items.index(potion_key))
    new_items = items.join(', ')

    # 업데이트
    @sheet_manager.update_user(user_id, { hp: new_hp, items: new_items })

    # 전투 중인지 확인
    battle_id = BattleState.find_battle_id_by_user(user_id)
    
    if battle_id
      state = BattleState.get(battle_id)
      
      if state && state[:current_turn].to_s == user_id.to_s
        # 전투 중 물약 사용
        hp_bar = create_hp_bar(new_hp, max_hp)
        
        message = "#{user_name}이(가) #{potion_type}물약 사용!\n"
        message += "HP +#{actual_heal} (#{current_hp} → #{new_hp})\n"
        message += "#{hp_bar} #{new_hp}/#{max_hp}\n"
        message += "━━━━━━━━━━━━━━━━━━\n"

        # 턴 넘기기
        if state[:type] == "2v2" || state[:type] == "4v4"
          state[:turn_index] += 1
          BattleState.update(battle_id, state)

          if state[:turn_index] >= state[:participants].length
            # 라운드 처리는 엔진에서
            require_relative '../core/battle_engine'
            engine = BattleEngine.new(@mastodon_client, @sheet_manager)
            engine.send(:process_team_round, battle_id, state, message)
          else
            state[:current_turn] = state[:turn_order][state[:turn_index]]
            BattleState.update(battle_id, state)
            
            next_player = @sheet_manager.find_user(state[:current_turn])
            next_player_name = next_player["이름"] || state[:current_turn]
            
            message += "#{next_player_name}의 차례\n"
            message += "[공격/@타겟] [방어/@타겟] [반격] [물약사용/크기/@타겟]"
            
            reply_to_battle(message, state)
          end
        else
          # 1:1 전투
          state[:current_turn] = state[:turn_order][(state[:turn_order].index(state[:current_turn]) + 1) % state[:turn_order].length]
          BattleState.update(battle_id, state)
          
          next_player = @sheet_manager.find_user(state[:current_turn])
          next_player_name = next_player ? (next_player["이름"] || state[:current_turn]) : state[:current_turn]
          
          message += "#{next_player_name}의 차례\n"
          message += "[공격] [방어] [반격] [물약사용/크기]"
          
          reply_to_battle(message, state)
        end
      end
    else
      # 평상시 물약 사용
      hp_bar = create_hp_bar(new_hp, max_hp)
      
      message = "#{user_name}이(가) #{potion_type}물약 사용!\n"
      message += "HP +#{actual_heal} (#{current_hp} → #{new_hp})\n"
      message += "#{hp_bar} #{new_hp}/#{max_hp}"
      
      @mastodon_client.reply(reply_status, message)
    end
  end

  # 타인에게 물약 사용 (팀전투 전용)
  def use_potion_for_target(user_id, reply_status, potion_type, target_id)
    unless potion_type
      @mastodon_client.reply(reply_status, "물약 크기를 지정하세요: [물약사용/소형/@대상]")
      return
    end

    user = @sheet_manager.find_user(user_id)
    target = @sheet_manager.find_user(target_id)
    
    unless user && target
      @mastodon_client.reply(reply_status, "사용자 정보를 찾을 수 없습니다.")
      return
    end

    user_name = user["이름"] || user_id
    target_name = target["이름"] || target_id
    heal_amount = POTION_HEAL[potion_type] || 10

    # 물약 소지 확인
    items = (user["아이템"] || "").split(',').map(&:strip)
    potion_key = "#{potion_type}물약"
    
    unless items.include?(potion_key)
      @mastodon_client.reply(reply_status, "#{user_name}은(는) #{potion_type}물약이 없습니다!")
      return
    end

    # 체력 계산
    vitality_stat = (target["체력"] || 0).to_i
    max_hp = 100 + (vitality_stat * 10)
    current_hp = (target["HP"] || 100).to_i
    new_hp = [current_hp + heal_amount, max_hp].min
    actual_heal = new_hp - current_hp

    # 물약 제거
    items.delete_at(items.index(potion_key))
    new_items = items.join(', ')

    # 업데이트
    @sheet_manager.update_user(user_id, { items: new_items })
    @sheet_manager.update_user(target_id, { hp: new_hp })

    # 전투 중인지 확인
    battle_id = BattleState.find_battle_id_by_user(user_id)
    
    if battle_id
      state = BattleState.get(battle_id)
      
      if state && state[:current_turn].to_s == user_id.to_s
        hp_bar = create_hp_bar(new_hp, max_hp)
        
        message = "#{user_name}이(가) #{target_name}에게 #{potion_type}물약 사용!\n"
        message += "HP +#{actual_heal} (#{current_hp} → #{new_hp})\n"
        message += "#{target_name}: #{hp_bar} #{new_hp}/#{max_hp}\n"
        message += "━━━━━━━━━━━━━━━━━━\n"

        # 턴 넘기기
        state[:turn_index] += 1
        BattleState.update(battle_id, state)

        if state[:turn_index] >= state[:participants].length
          require_relative '../core/battle_engine'
          engine = BattleEngine.new(@mastodon_client, @sheet_manager)
          engine.send(:process_team_round, battle_id, state, message)
        else
          state[:current_turn] = state[:turn_order][state[:turn_index]]
          BattleState.update(battle_id, state)
          
          next_player = @sheet_manager.find_user(state[:current_turn])
          next_player_name = next_player["이름"] || state[:current_turn]
          
          message += "#{next_player_name}의 차례\n"
          message += "[공격/@타겟] [방어/@타겟] [반격] [물약사용/크기/@타겟]"
          
          reply_to_battle(message, state)
        end
      end
    end
  end

  private

  def create_hp_bar(current_hp, max_hp)
    percentage = [current_hp.to_f / max_hp, 1.0].min
    filled_length = (percentage * 10).round
    
    filled = "█" * filled_length
    empty = "░" * (10 - filled_length)
    
    filled + empty
  end

  def reply_to_battle(message, state)
    return unless state[:reply_status]
    participants = state[:participants]
    @mastodon_client.reply_with_mentions(state[:reply_status], message, participants)
  end
end
