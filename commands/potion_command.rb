require_relative '../core/battle_state'

class PotionCommand
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

    items = user["아이템"] || user[:items] || ""
    unless items.include?("포션") || items.include?("물약")
      message = "포션이 없습니다."
      reply_to_battle(message, state)
      return
    end

    heal_amount = [5, 10, 15, 20].sample
    current_hp = (user["HP"] || user[:hp] || 100).to_i
    new_hp = [current_hp + heal_amount, 100].min

    # HP 업데이트
    @sheet_manager.update_user(user_id, { hp: new_hp })

    # 아이템에서 포션 제거
    new_items = items.sub(/포션|물약/, "").strip
    @sheet_manager.update_user(user_id, { items: new_items })

    user_name = user["이름"] || user[:name] || user_id
    message = "#{user_name}이(가) 물약을 사용했습니다. (회복량: #{heal_amount}, 현재 체력: #{new_hp})"
    reply_to_battle(message, state)

    # 턴 넘기기
    state[:current_turn] = state[:turn_order][(state[:turn_order].index(state[:current_turn]) + 1) % state[:turn_order].length]
    
    # 다음 턴이 허수아비면 자동 진행 (상태만 변경, 실제 진행은 battle_engine에서)
    if state[:current_turn].to_s.include?("허수아비")
      # BattleEngine의 dummy_turn이 자동으로 호출되도록 상태만 설정
    else
      # 다음 플레이어 선택지 표시
      next_player = @sheet_manager.find_user(state[:current_turn])
      next_player_name = next_player ? (next_player["이름"] || next_player[:name] || state[:current_turn]) : state[:current_turn]
      
      choice_message = "\n━━━━━━━━━━━━━━━━━━\n"
      choice_message += "#{next_player_name}의 차례\n"
      choice_message += "[공격] - 상대방 공격\n"
      choice_message += "[방어] - 방어 자세 (피해 50% 감소)\n"
      choice_message += "[반격] - 피격 시 반격 (고정 5 데미지)\n"
      choice_message += "[물약사용] - 체력 회복 (5/10/15/20)\n"
      choice_message += "[도주] - 전투 탈출\n"
      choice_message += "━━━━━━━━━━━━━━━━━━"
      
      reply_to_battle(choice_message, state)
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
