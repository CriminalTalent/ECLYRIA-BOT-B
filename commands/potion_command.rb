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
    use_potion_internal(user_id, reply_status, user_id, potion_type)
  end

  def use_potion_for_target(user_id, reply_status, potion_type, target_id)
    target_id = target_id.gsub('@', '').strip
    use_potion_internal(user_id, reply_status, target_id, potion_type)
  end

  private

  # reply_status == battle_id
  def use_potion_internal(user_id, battle_id, target_id, potion_type)
    state = BattleState.get(battle_id)
    in_battle = !state.nil?

    # 유저 확인
    user = @sheet_manager.find_user(user_id)
    target = @sheet_manager.find_user(target_id)

    unless user
      @mastodon_client.reply(battle_id, "사용자 정보를 찾을 수 없습니다.")
      return
    end

    unless target
      @mastodon_client.reply(battle_id, "대상을 찾을 수 없습니다.")
      return
    end

    # 전투 중이면 battle_id 검사 및 턴 검사
    if in_battle
      user_battle = BattleState.battle_of(user_id)
      if user_battle != battle_id
        @mastodon_client.reply(battle_id, "이 전투의 참가자가 아닙니다.")
        return
      end

      if state[:current_turn].to_s != user_id.to_s
        @mastodon_client.reply(battle_id, "당신의 턴이 아닙니다.")
        return
      end

      unless state[:participants].include?(target_id)
        @mastodon_client.reply(battle_id, "전투 참가자가 아닙니다.")
        return
      end
    end

    # 아이템 목록
    user_items = @sheet_manager.find_user_items(user_id)
    unless user_items
      no_potion(user_id, user, state, battle_id)
      return
    end

    items = (user_items["아이템"] || "").strip
    items_clean = items.gsub(/\s+/, "")

    available = POTION_TYPES.keys.select do |p|
      items_clean.include?(p.gsub(/\s+/, ""))
    end

    # 물약 종류 선택이 없을 때 → 목록 출력
    if potion_type.nil?
      show_potion_list(user, target, available, battle_id, state, user_id, target_id)
      return
    end

    # 물약 타입 검색
    potion_found = find_potion(potion_type, items_clean)
    unless potion_found
      @mastodon_client.reply(battle_id, "#{user['이름'] || user_id}은(는) 해당 종류의 물약이 없습니다. [물약]으로 목록 확인")
      return
    end

    # HP 회복 계산
    heal_amount = POTION_TYPES[potion_found]
    current_hp = (target["HP"] || 100).to_i
    new_hp = [current_hp + heal_amount, 100].min
    actual_heal = new_hp - current_hp

    @sheet_manager.update_user(target_id, { hp: new_hp })

    # 아이템 제거
    new_items = items.sub(potion_found, "").gsub(/,+/, ",").gsub(/^,|,$/, "").strip
    @sheet_manager.update_user_items(user_id, { items: new_items })

    # 메시지 구성
    user_name = user["이름"] || user_id
    target_name = target["이름"] || target_id
    potion_display = potion_found.gsub('물약', ' 물약').strip

    msg = if user_id == target_id
      "#{user_name}이 #{potion_display}을 사용했습니다.\n회복: #{actual_heal} (#{current_hp} → #{new_hp})"
    else
      "#{user_name}이 #{target_name}에게 #{potion_display}을 사용했습니다.\n회복: #{actual_heal} (#{current_hp} → #{new_hp})"
    end

    # 전투 중이면 턴 진행
    if in_battle
      turn_in_battle(state, battle_id, msg)
    else
      @mastodon_client.reply(battle_id, msg)
    end
  end

  def no_potion(user_id, user, state, battle_id)
    user_name = user["이름"] || user_id
    msg = "#{user_name}은(는) 물약이 없습니다."

    if state
      turn_in_battle(state, battle_id, msg)
    else
      @mastodon_client.reply(battle_id, msg)
    end
  end

  # 턴 전환 공통 처리
  def turn_in_battle(state, battle_id, msg)
    msg += "\n━━━━━━━━━━━━━━━━━━"

    if state[:type] == "2v2"
      state[:turn_index] += 1
      if state[:turn_index] >= state[:turn_order].length
        require_relative '../core/battle_engine'
        engine = BattleEngine.new(@mastodon_client, @sheet_manager)
        engine.send(:process_2v2_round, state, msg)
      else
        state[:current_turn] = state[:turn_order][state[:turn_index]]
        reply_to_battle(msg, state, battle_id)
      end
    else
      BattleState.next_turn(battle_id)
      reply_to_battle(msg, state, battle_id)
    end
  end

  def find_potion(input, items_clean)
    return "소형물약" if input =~ /소형/i && items_clean.include?("소형물약")
    return "중형물약" if input =~ /중형/i && items_clean.include?("중형물약")
    return "대형물약" if input =~ /대형/i && items_clean.include?("대형물약")
    nil
  end

  def show_potion_list(user, target, available, battle_id, state, user_id, target_id)
    user_name = user["이름"] || user_id
    target_name = target["이름"] || target_id

    msg = "#{user_name}의 물약 목록:\n"
    msg += "━━━━━━━━━━━━━━━━━━\n"
    available.each do |p|
      heal = POTION_TYPES[p]
      msg += "• #{p.gsub('물약', ' 물약')} (회복: #{heal})\n"
    end
    msg += "━━━━━━━━━━━━━━━━━━\n사용법:\n"

    if user_id == target_id
      available.each do |p|
        key = p.gsub('물약', '')
        msg += "[물약/#{key}]\n"
      end
    else
      available.each do |p|
        key = p.gsub('물약', '')
        msg += "[물약/#{key}/@#{target_id}]\n"
      end
    end

    if state
      reply_to_battle(msg, state, battle_id)
    else
      @mastodon_client.reply(battle_id, msg)
    end
  end

  def reply_to_battle(message, state, battle_id)
    participants = state[:participants].reject { |p| p.include?("허수아비") }
    @mastodon_client.reply_with_mentions(battle_id, message, participants)
  end
end
