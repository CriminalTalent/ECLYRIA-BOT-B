require_relative '../core/battle_state'

class PotionCommand
  # 물약 종류별 회복량 (고정값)
  POTION_TYPES = {
    "소형 포션" => 20,
    "중형 포션" => 40,
    "대형 포션" => 60,
    "포션" => 20,      # 기본 포션
    "물약" => 20        # 기본 물약
  }

  def initialize(mastodon_client, sheet_manager)
    @mastodon_client = mastodon_client
    @sheet_manager = sheet_manager
  end

  def use_potion(user_id, reply_status)
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

    # 아이템 확인 및 물약 찾기
    items = user["아이템"] || user[:items] || ""
    potion_found = nil
    heal_amount = 0

    # 우선순위: 대형 → 중형 → 소형 → 기본
    POTION_TYPES.keys.reverse.each do |potion_type|
      if items.include?(potion_type)
        potion_found = potion_type
        heal_amount = POTION_TYPES[potion_type]
        break
      end
    end

    # 물약이 없으면 자동으로 턴 넘김
    unless potion_found
      user_name = user["이름"] || user[:name] || user_id
      message = "#{user_name}은(는) 포션이 없습니다! 턴을 넘깁니다.\n"
      message += "━━━━━━━━━━━━━━━━━━\n"
      
      # 턴 넘기기
      state[:current_turn] = state[:turn_order][(state[:turn_order].index(state[:current_turn]) + 1) % state[:turn_order].length]
      
      # 다음 턴 안내
      if state[:current_turn].to_s.include?("허수아비")
        reply_to_battle(message, state)
        # 허수아비 턴은 battle_engine에서 자동 처리됨
      else
        next_player = @sheet_manager.find_user(state[:current_turn])
        next_player_name = next_player ? (next_player["이름"] || next_player[:name] || state[:current_turn]) : state[:current_turn]
        
        message += "#{next_player_name}의 차례\n"
        message += "[공격] [방어] [반격] [물약사용] [도주]"
        
        reply_to_battle(message, state)
      end
      return
    end

    # 회복 처리
    current_hp = (user["HP"] || user[:hp] || 100).to_i
    new_hp = [current_hp + heal_amount, 100].min
    actual_heal = new_hp - current_hp

    # HP 업데이트
    @sheet_manager.update_user(user_id, { hp: new_hp })

    # 아이템에서 포션 제거
    new_items = items.sub(potion_found, "").gsub(/,+/, ",").gsub(/^,|,$/, "").strip
    @sheet_manager.update_user(user_id, { items: new_items })

    user_name = user["이름"] || user[:name] || user_id
    message = "#{user_name}이(가) #{potion_found}을 사용했습니다.\n"
    message += "회복: #{actual_heal} (#{current_hp} → #{new_hp})\n"
    message += "━━━━━━━━━━━━━━━━━━\n"

    # 턴 넘기기
    state[:current_turn] = state[:turn_order][(state[:turn_order].index(state[:current_turn]) + 1) % state[:turn_order].length]
    
    # 다음 턴이 허수아비면 자동 진행
    if state[:current_turn].to_s.include?("허수아비")
      reply_to_battle(message, state)
      # BattleEngine의 dummy_turn이 자동으로 호출되도록 상태만 설정
    else
      # 다음 플레이어 선택지 표시
      next_player = @sheet_manager.find_user(state[:current_turn])
      next_player_name = next_player ? (next_player["이름"] || next_player[:name] || state[:current_turn]) : state[:current_turn]
      
      message += "#{next_player_name}의 차례\n"
      message += "[공격] [방어] [반격] [물약사용] [도주]"
      
      reply_to_battle(message, state)
    end
  end

  private

  # === 전투 스레드에 답글 (참여자 멘션) ===
  def reply_to_battle(message, state)
    return unless state[:reply_status]
    participants = state[:participants].reject { |p| p.include?("허수아비") }
    @mastodon_client.reply_with_mentions(state[:reply_status], message, participants)
  end
end
