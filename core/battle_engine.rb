require_relative 'battle_state'

class BattleEngine
  def initialize(mastodon_client, sheet_manager)
    @mastodon_client = mastodon_client
    @sheet_manager = sheet_manager
  end

  def check_hp(user_id, status)
    user = @sheet_manager.find_user(user_id)

    unless user
      @mastodon_client.reply(status, "등록되지 않은 사용자입니다.")
      return
    end

    user_name = user["이름"] || user_id
    current_hp = (user["체력"] || "100").to_i
    max_hp = (user["최대체력"] || "100").to_i
    hp_stat = (user["체력스탯"] || "0").to_i
    hp_percent = (current_hp.to_f / max_hp * 100).round(1)

    # HP 바 생성 (10칸)
    filled_bars = (hp_percent / 10).round
    hp_bar = "█" * filled_bars + "░" * (10 - filled_bars)

    message = "━━━━━━━━━━━━━━━━━━\n"
    message += "#{user_name}의 상태\n"
    message += "━━━━━━━━━━━━━━━━━━\n\n"
    message += "HP: #{current_hp} / #{max_hp} (#{hp_percent}%)\n"
    message += "#{hp_bar}\n\n"
    message += "체력 스탯: #{hp_stat}"

    @mastodon_client.reply(status, message)
  end

  def start_pvp(status, participants, is_gm: false, gm_user: nil)
    thread_id = status[:in_reply_to_id] || status[:id]
    
    puts "[전투] 전투 시작 요청"
    puts "[전투] status_id: #{status[:id]}"
    puts "[전투] in_reply_to_id: #{status[:in_reply_to_id]}"
    puts "[전투] thread_id: #{thread_id}"
    puts "[전투] 참가자: #{participants.inspect}"

    if BattleState.find_by_thread(thread_id)
      @mastodon_client.reply(status, "이 스레드에서 이미 전투가 진행 중입니다.")
      return
    end

    case participants.length
    when 2
      start_1v1(status, participants, thread_id, gm_user)
    when 4
      start_2v2(status, participants, thread_id, gm_user)
    when 8
      start_4v4(status, participants, thread_id, gm_user)
    else
      @mastodon_client.reply(status, "1:1(2명), 2:2(4명), 4:4(8명) 전투만 지원합니다.")
    end
  end

  def attack(user_id, status, target_id = nil)
    thread_id = status[:in_reply_to_id] || status[:id]
    
    puts "[공격] 공격 시도"
    puts "[공격] user_id: #{user_id}"
    puts "[공격] status_id: #{status[:id]}"
    puts "[공격] in_reply_to_id: #{status[:in_reply_to_id]}"
    puts "[공격] thread_id: #{thread_id}"
    
    battle = BattleState.find_by_thread(thread_id)
    
    # thread_id로 못 찾으면 참가자로 찾기
    if !battle
      puts "[공격] thread_id로 못 찾음, 참가자로 검색..."
      battle = BattleState.find_by_participant(user_id)
      puts "[공격] 참가자로 찾기 결과: #{battle ? '찾음' : '못 찾음'}"
    end
    
    puts "[공격] 전투 찾기 최종 결과: #{battle ? '찾음' : '못 찾음'}"
    if battle
      puts "[공격] 찾은 전투 thread_id: #{battle[:thread_id]}"
      puts "[공격] 현재 턴: #{battle[:current_turn]}"
    end

    unless battle
      @mastodon_client.reply(status, "진행 중인 전투가 없습니다.")
      return
    end

    unless battle[:current_turn] == user_id
      @mastodon_client.reply(status, "당신의 차례가 아닙니다.")
      return
    end

    attacker = @sheet_manager.find_user(user_id)
    unless attacker
      @mastodon_client.reply(status, "등록되지 않은 사용자입니다.")
      return
    end

    team_mode = battle[:team_a].any?

    if team_mode && !target_id
      @mastodon_client.reply(status, "팀 전투에서는 [공격/@타겟] 형식으로 타겟을 지정해야 합니다.")
      return
    end

    if team_mode
      my_team = battle[:team_a].include?(user_id) ? battle[:team_a] : battle[:team_b]
      enemy_team = battle[:team_a].include?(user_id) ? battle[:team_b] : battle[:team_a]

      unless enemy_team.include?(target_id)
        @mastodon_client.reply(status, "적 팀의 멤버만 공격할 수 있습니다.")
        return
      end

      # 대리방어 체크
      original_target_id = target_id
      if battle[:protect] && battle[:protect][target_id]
        protector_id = battle[:protect][target_id]
        # 대리방어자가 아직 살아있는지 확인
        if enemy_team.include?(protector_id)
          target_id = protector_id
          has_protector = true
          protector_name = @sheet_manager.find_user(protector_id)["이름"] || protector_id
          original_target_name = @sheet_manager.find_user(original_target_id)["이름"] || original_target_id
        end
      end

      defender = @sheet_manager.find_user(target_id)
    else
      target_id = battle[:participants].find { |p| p != user_id }
      defender = @sheet_manager.find_user(target_id)
    end

    unless defender
      @mastodon_client.reply(status, "대상을 찾을 수 없습니다.")
      return
    end

    result = execute_combat(attacker, user_id, defender, target_id, battle)

    message = ""
    if has_protector
      message += "#{protector_name}이(가) #{original_target_name}을(를) 보호합니다!\n\n"
    end
    message += build_attack_message(result, attacker, defender, user_id, target_id)

    # 대리방어 사용 후 protect 정보 삭제
    if has_protector && battle[:protect]
      battle[:protect].delete(original_target_id)
    end

    if result[:defender_hp] <= 0
      handle_defeat(battle, target_id, status, message)
    else
      next_turn_user = get_next_turn(battle)
      BattleState.update(battle[:battle_id], {
        current_turn: next_turn_user,
        guarded: {},
        counter: {},
        protect: battle[:protect] || {}
      })

      next_user_data = @sheet_manager.find_user(next_turn_user)
      next_user_name = next_user_data["이름"] || next_turn_user

      message += build_hp_status(battle)
      
      team_mode = battle[:team_a].any?
      message += "\n\n#{next_user_name}의 차례\n"
      if team_mode
        message += "[공격/@타겟] [방어] [방어/@아군] [반격] [물약사용/크기] [도주]"
      else
        message += "[공격] [방어] [반격] [물약사용/크기] [도주]"
      end

      @mastodon_client.reply_with_mentions(status, message, battle[:participants])
    end
  end

  def defend(user_id, status, target_id = nil)
    thread_id = status[:in_reply_to_id] || status[:id]
    battle = BattleState.find_by_thread(thread_id)
    
    # thread_id로 못 찾으면 참가자로 찾기
    battle = BattleState.find_by_participant(user_id) unless battle

    unless battle
      @mastodon_client.reply(status, "진행 중인 전투가 없습니다.")
      return
    end

    unless battle[:current_turn] == user_id
      @mastodon_client.reply(status, "당신의 차례가 아닙니다.")
      return
    end

    user = @sheet_manager.find_user(user_id)
    user_name = user["이름"] || user_id

    # 대리 방어인 경우
    if target_id
      team_mode = battle[:team_a].any?

      unless team_mode
        @mastodon_client.reply(status, "1:1 전투에서는 대리 방어를 사용할 수 없습니다.")
        return
      end

      target_user = @sheet_manager.find_user(target_id)
      unless target_user
        @mastodon_client.reply(status, "대상을 찾을 수 없습니다.")
        return
      end

      # 팀 확인
      my_team = battle[:team_a].include?(user_id) ? battle[:team_a] : battle[:team_b]
      unless my_team.include?(target_id)
        @mastodon_client.reply(status, "같은 팀원만 보호할 수 있습니다.")
        return
      end

      target_name = target_user["이름"] || target_id

      # protect 정보 저장
      battle[:protect] ||= {}
      battle[:protect][target_id] = user_id

      next_turn_user = get_next_turn(battle)

      BattleState.update(battle[:battle_id], {
        current_turn: next_turn_user,
        protect: battle[:protect],
        guarded: battle[:guarded] || {},
        counter: {}
      })

      next_user_data = @sheet_manager.find_user(next_turn_user)
      next_user_name = next_user_data["이름"] || next_turn_user

      message = "#{user_name}이(가) #{target_name}을(를) 보호하는 태세를 취했습니다.\n"
      message += "다음 공격 시 #{user_name}이(가) 대신 받습니다."
      message += build_hp_status(battle)
      message += "\n\n#{next_user_name}의 차례\n[공격/@타겟] [방어] [방어/@아군] [반격] [물약사용/크기] [도주]"

      @mastodon_client.reply_with_mentions(status, message, battle[:participants])
    else
      # 일반 방어
      battle[:guarded] ||= {}
      battle[:guarded][user_id] = true

      next_turn_user = get_next_turn(battle)

      BattleState.update(battle[:battle_id], {
        current_turn: next_turn_user,
        guarded: battle[:guarded],
        counter: {},
        protect: battle[:protect] || {}
      })

      next_user_data = @sheet_manager.find_user(next_turn_user)
      next_user_name = next_user_data["이름"] || next_turn_user

      team_mode = battle[:team_a].any?
      message = "#{user_name}이(가) 방어 태세를 취했습니다."
      message += build_hp_status(battle)
      message += "\n\n#{next_user_name}의 차례\n"
      if team_mode
        message += "[공격/@타겟] [방어] [방어/@아군] [반격] [물약사용/크기] [도주]"
      else
        message += "[공격] [방어] [반격] [물약사용/크기] [도주]"
      end

      @mastodon_client.reply_with_mentions(status, message, battle[:participants])
    end
  end

  def counter(user_id, status)
    thread_id = status[:in_reply_to_id] || status[:id]
    battle = BattleState.find_by_thread(thread_id)
    
    # thread_id로 못 찾으면 참가자로 찾기
    battle = BattleState.find_by_participant(user_id) unless battle

    unless battle
      @mastodon_client.reply(status, "진행 중인 전투가 없습니다.")
      return
    end

    unless battle[:current_turn] == user_id
      @mastodon_client.reply(status, "당신의 차례가 아닙니다.")
      return
    end

    user = @sheet_manager.find_user(user_id)
    user_name = user["이름"] || user_id

    battle[:counter][user_id] = true
    next_turn_user = get_next_turn(battle)

    BattleState.update(battle[:battle_id], {
      current_turn: next_turn_user,
      counter: battle[:counter],
      guarded: {}
    })

    next_user_data = @sheet_manager.find_user(next_turn_user)
    next_user_name = next_user_data["이름"] || next_turn_user

    message = "#{user_name}이(가) 반격 태세를 취했습니다."
    message += build_hp_status(battle)
    message += "\n\n#{next_user_name}의 차례\n[공격] [방어] [반격] [물약사용/크기] [도주]"

    @mastodon_client.reply_with_mentions(status, message, battle[:participants])
  end

  def flee(user_id, status)
    thread_id = status[:in_reply_to_id] || status[:id]
    battle = BattleState.find_by_thread(thread_id)
    
    # thread_id로 못 찾으면 참가자로 찾기
    battle = BattleState.find_by_participant(user_id) unless battle

    unless battle
      @mastodon_client.reply(status, "진행 중인 전투가 없습니다.")
      return
    end

    unless battle[:current_turn] == user_id
      @mastodon_client.reply(status, "당신의 차례가 아닙니다.")
      return
    end

    user = @sheet_manager.find_user(user_id)
    user_name = user["이름"] || user_id

    user_agi = (user["민첩"] || 10).to_i
    flee_roll = rand(1..20)
    flee_total = user_agi + flee_roll

    message = "#{user_name}의 도주 시도\n"
    message += "민첩: #{user_agi} + D20: #{flee_roll} = #{flee_total}\n\n"

    if flee_total >= 15
      message += "도주에 성공했습니다.\n전투가 종료되었습니다."
      BattleState.delete(battle[:battle_id])
      @mastodon_client.reply_with_mentions(status, message, battle[:participants])
    else
      message += "도주에 실패했습니다."
      
      next_turn_user = get_next_turn(battle)
      BattleState.update(battle[:battle_id], {
        current_turn: next_turn_user,
        guarded: {},
        counter: {}
      })

      next_user_data = @sheet_manager.find_user(next_turn_user)
      next_user_name = next_user_data["이름"] || next_turn_user
      
      message += build_hp_status(battle)
      message += "\n\n#{next_user_name}의 차례\n[공격] [방어] [반격] [물약사용/크기] [도주]"

      @mastodon_client.reply_with_mentions(status, message, battle[:participants])
    end
  end

  def use_potion(user_id, status, potion_size, target_id = nil)
    thread_id = status[:in_reply_to_id] || status[:id]
    battle = BattleState.find_by_thread(thread_id)
    
    # thread_id로 못 찾으면 참가자로 찾기
    battle = BattleState.find_by_participant(user_id) unless battle

    user = @sheet_manager.find_user(user_id)
    unless user
      @mastodon_client.reply(status, "등록되지 않은 사용자입니다.")
      return
    end

    items = (user["아이템"] || "").split(',').map(&:strip)

    # 물약 크기별 정확한 이름 매칭
    potion_name_to_find = case potion_size
                          when /소형/i then "소형물약"
                          when /중형/i then "중형물약"
                          when /대형/i then "대형물약"
                          else nil
                          end

    unless potion_name_to_find
      @mastodon_client.reply(status, "물약 크기를 지정해주세요. (소형/중형/대형)")
      return
    end

    # 정확히 일치하는 물약 찾기
    potion_idx = items.find_index { |item| item == potion_name_to_find }

    unless potion_idx
      @mastodon_client.reply(status, "#{potion_name_to_find}을(를) 보유하고 있지 않습니다.")
      return
    end

    # 크기별 회복량 (HP 100-200 기준)
    heal_amount = case potion_size
                  when /소형/i then 10
                  when /중형/i then 20
                  when /대형/i then 50
                  else 10
                  end

    if battle
      unless battle[:current_turn] == user_id
        @mastodon_client.reply(status, "당신의 차례가 아닙니다.")
        return
      end

      actual_target = target_id || user_id
      target_user = @sheet_manager.find_user(actual_target)

      unless target_user
        @mastodon_client.reply(status, "대상을 찾을 수 없습니다.")
        return
      end

      unless battle[:participants].include?(actual_target)
        @mastodon_client.reply(status, "전투 참가자만 회복할 수 있습니다.")
        return
      end

      current_hp = (target_user["체력"] || "100").to_i
      max_hp = (target_user["최대체력"] || "100").to_i
      new_hp = [current_hp + heal_amount, max_hp].min
      @sheet_manager.update_user_hp(actual_target, new_hp)

      items.delete_at(potion_idx)
      update_user_items(user_id, items)

      user_name = user["이름"] || user_id
      target_name = target_user["이름"] || actual_target

      message = "#{user_name}이(가) #{potion_name_to_find}을(를) 사용했습니다.\n"
      if actual_target == user_id
        message += "#{target_name}의 체력이 #{heal_amount} 회복되었습니다.\n"
      else
        message += "#{target_name}을(를) 치료했습니다. 체력 +#{heal_amount}\n"
      end
      message += "현재 HP: #{new_hp}"

      next_turn_user = get_next_turn(battle)
      BattleState.update(battle[:battle_id], {
        current_turn: next_turn_user,
        guarded: {},
        counter: {}
      })

      next_user_data = @sheet_manager.find_user(next_turn_user)
      next_user_name = next_user_data["이름"] || next_turn_user
      
      message += build_hp_status(battle)
      message += "\n\n#{next_user_name}의 차례\n[공격] [방어] [반격] [물약사용/크기] [도주]"

      @mastodon_client.reply_with_mentions(status, message, battle[:participants])
    else
      actual_target = target_id || user_id
      target_user = @sheet_manager.find_user(actual_target)

      unless target_user
        @mastodon_client.reply(status, "대상을 찾을 수 없습니다.")
        return
      end

      current_hp = (target_user["체력"] || "100").to_i
      max_hp = (target_user["최대체력"] || "100").to_i
      new_hp = [current_hp + heal_amount, max_hp].min
      @sheet_manager.update_user_hp(actual_target, new_hp)

      items.delete_at(potion_idx)
      update_user_items(user_id, items)

      user_name = user["이름"] || user_id
      target_name = target_user["이름"] || actual_target

      message = "#{user_name}이(가) #{potion_name_to_find}을(를) 사용했습니다.\n"
      if actual_target == user_id
        message += "체력이 #{heal_amount} 회복되었습니다.\n"
      else
        message += "#{target_name}을(를) 치료했습니다. 체력 +#{heal_amount}\n"
      end
      message += "현재 HP: #{new_hp}"

      @mastodon_client.reply(status, message)
    end
  end

  def stop_battle(user_id, status)
    thread_id = status[:in_reply_to_id] || status[:id]
    battle = BattleState.find_by_thread(thread_id)
    
    # thread_id로 못 찾으면 참가자로 찾기
    battle = BattleState.find_by_participant(user_id) unless battle

    unless battle
      @mastodon_client.reply(status, "진행 중인 전투가 없습니다.")
      return
    end

    unless battle[:gm_user] == user_id
      @mastodon_client.reply(status, "전투를 개설한 GM만 중단할 수 있습니다.")
      return
    end

    BattleState.delete(battle[:battle_id])
    message = "GM이 전투를 중단했습니다."
    @mastodon_client.reply_with_mentions(status, message, battle[:participants])
  end

  private

  def build_hp_status(battle)
    message = "\n━━━━━━━━━━━━━━━━━━\n"
    message += "현재 체력\n"
    
    team_mode = battle[:team_a].any?
    
    if team_mode
      # 팀 모드
      message += "━━━━━━━━━━━━━━━━━━\n"
      
      # 팀 A
      team_a_alive = battle[:team_a].select { |id| battle[:participants].include?(id) }
      team_a_alive.each do |user_id|
        user = @sheet_manager.find_user(user_id)
        name = user["이름"] || user_id
        hp = user["체력"].to_i
        max_hp = user["최대체력"].to_i
        hp_percent = (hp.to_f / max_hp * 100).round(0)
        
        bar_length = 10
        filled = (hp_percent / 10.0).round
        bar = "█" * filled + "░" * (bar_length - filled)
        
        message += "#{name}: #{hp}/#{max_hp} #{bar}\n"
      end
      
      message += "━━━━━━━━━━━━━━━━━━\n"
      
      # 팀 B
      team_b_alive = battle[:team_b].select { |id| battle[:participants].include?(id) }
      team_b_alive.each do |user_id|
        user = @sheet_manager.find_user(user_id)
        name = user["이름"] || user_id
        hp = user["체력"].to_i
        max_hp = user["최대체력"].to_i
        hp_percent = (hp.to_f / max_hp * 100).round(0)
        
        bar_length = 10
        filled = (hp_percent / 10.0).round
        bar = "█" * filled + "░" * (bar_length - filled)
        
        message += "#{name}: #{hp}/#{max_hp} #{bar}\n"
      end
    else
      # 1:1 모드
      battle[:participants].each do |user_id|
        user = @sheet_manager.find_user(user_id)
        name = user["이름"] || user_id
        hp = user["체력"].to_i
        max_hp = user["최대체력"].to_i
        hp_percent = (hp.to_f / max_hp * 100).round(0)
        
        bar_length = 10
        filled = (hp_percent / 10.0).round
        bar = "█" * filled + "░" * (bar_length - filled)
        
        message += "#{name}: #{hp}/#{max_hp} #{bar}\n"
      end
    end
    
    message += "━━━━━━━━━━━━━━━━━━"
    message
  end

  def start_1v1(status, participants, thread_id, gm_user)
    user_a_id, user_b_id = participants
    user_a = @sheet_manager.find_user(user_a_id)
    user_b = @sheet_manager.find_user(user_b_id)

    unless user_a && user_b
      @mastodon_client.reply(status, "등록되지 않은 사용자가 포함되어 있습니다.")
      return
    end

    user_a_agi = (user_a["민첩"] || 10).to_i + rand(1..20)
    user_b_agi = (user_b["민첩"] || 10).to_i + rand(1..20)
    turn_order = user_a_agi >= user_b_agi ? [user_a_id, user_b_id] : [user_b_id, user_a_id]

    battle_id = BattleState.create(
      thread_id,
      participants,
      {
        turn_order: turn_order,
        current_turn: turn_order[0],
        reply_status: status,
        gm_user: gm_user
      }
    )

    puts "[전투] 1:1 전투 생성 완료 - battle_id: #{battle_id}"

    user_a_name = user_a["이름"] || user_a_id
    user_b_name = user_b["이름"] || user_b_id
    first_turn_name = turn_order[0] == user_a_id ? user_a_name : user_b_name

    message = "━━━━━━━━━━━━━━━━━━\n"
    message += "1:1 전투 시작\n"
    message += "#{user_a_name} vs #{user_b_name}\n"
    message += "선공: #{first_turn_name}\n"
    message += "━━━━━━━━━━━━━━━━━━\n\n"
    message += "#{first_turn_name}의 차례\n[공격] [방어] [반격] [물약사용/크기] [도주]"

    @mastodon_client.reply_with_mentions(status, message, participants)
  end

  def start_2v2(status, participants, thread_id, gm_user)
    team_a = participants[0..1]
    team_b = participants[2..3]

    all_users = participants.map { |id| @sheet_manager.find_user(id) }
    unless all_users.all?
      @mastodon_client.reply(status, "등록되지 않은 사용자가 포함되어 있습니다.")
      return
    end

    agility_data = participants.map do |user_id|
      user = @sheet_manager.find_user(user_id)
      agi = (user["민첩"] || 10).to_i + rand(1..20)
      { user_id: user_id, agi: agi }
    end

    turn_order = agility_data.sort_by { |d| -d[:agi] }.map { |d| d[:user_id] }

    battle_id = BattleState.create(
      thread_id,
      participants,
      {
        team_a: team_a,
        team_b: team_b,
        turn_order: turn_order,
        current_turn: turn_order[0],
        reply_status: status,
        gm_user: gm_user
      }
    )

    team_a_names = team_a.map { |id| @sheet_manager.find_user(id)["이름"] || id }
    team_b_names = team_b.map { |id| @sheet_manager.find_user(id)["이름"] || id }
    first_turn_user = @sheet_manager.find_user(turn_order[0])
    first_turn_name = first_turn_user["이름"] || turn_order[0]

    message = "━━━━━━━━━━━━━━━━━━\n"
    message += "2:2 전투 시작\n"
    message += "팀A: #{team_a_names.join(', ')}\n"
    message += "팀B: #{team_b_names.join(', ')}\n"
    message += "선공: #{first_turn_name}\n"
    message += "━━━━━━━━━━━━━━━━━━\n\n"
    message += "#{first_turn_name}의 차례\n[공격/@타겟] [방어] [방어/@아군] [반격] [물약사용/크기] [도주]"

    @mastodon_client.reply_with_mentions(status, message, participants)
  end

  def start_4v4(status, participants, thread_id, gm_user)
    team_a = participants[0..3]
    team_b = participants[4..7]

    all_users = participants.map { |id| @sheet_manager.find_user(id) }
    unless all_users.all?
      @mastodon_client.reply(status, "등록되지 않은 사용자가 포함되어 있습니다.")
      return
    end

    agility_data = participants.map do |user_id|
      user = @sheet_manager.find_user(user_id)
      agi = (user["민첩"] || 10).to_i + rand(1..20)
      { user_id: user_id, agi: agi }
    end

    turn_order = agility_data.sort_by { |d| -d[:agi] }.map { |d| d[:user_id] }

    battle_id = BattleState.create(
      thread_id,
      participants,
      {
        team_a: team_a,
        team_b: team_b,
        turn_order: turn_order,
        current_turn: turn_order[0],
        reply_status: status,
        gm_user: gm_user
      }
    )

    team_a_names = team_a.map { |id| @sheet_manager.find_user(id)["이름"] || id }
    team_b_names = team_b.map { |id| @sheet_manager.find_user(id)["이름"] || id }
    first_turn_user = @sheet_manager.find_user(turn_order[0])
    first_turn_name = first_turn_user["이름"] || turn_order[0]

    message = "━━━━━━━━━━━━━━━━━━\n"
    message += "4:4 전투 시작\n"
    message += "팀A: #{team_a_names.join(', ')}\n"
    message += "팀B: #{team_b_names.join(', ')}\n"
    message += "선공: #{first_turn_name}\n"
    message += "━━━━━━━━━━━━━━━━━━\n\n"
    message += "#{first_turn_name}의 차례\n[공격/@타겟] [방어] [방어/@아군] [반격] [물약사용/크기] [도주]"

    @mastodon_client.reply_with_mentions(status, message, participants)
  end

  def execute_combat(attacker, attacker_id, defender, defender_id, battle)
    attacker_name = attacker["이름"] || attacker_id
    defender_name = defender["이름"] || defender_id

    atk_stat = (attacker["공격"] || 10).to_i
    atk_roll = rand(1..20)
    luck = (attacker["행운"] || 10).to_i

    crit_threshold = [(20 - luck / 2), 2].max
    is_crit = atk_roll >= crit_threshold

    atk_total = atk_stat + atk_roll

    def_stat = (defender["방어"] || 10).to_i
    def_roll = rand(1..20)
    def_total = def_stat + def_roll

    is_guarded = battle[:guarded][defender_id]
    is_counter = battle[:counter][defender_id]

    # 방어 태세일 경우 방어 판정에 추가 보너스
    if is_guarded
      def_bonus_roll = rand(1..20)
      def_total += def_bonus_roll
      def_bonus = def_bonus_roll
    end

    # 데미지 계산: 공격 - 방어
    damage = [atk_total - def_total, 0].max
    damage = (damage * 1.5).to_i if is_crit

    current_hp = (defender["체력"] || "100").to_i
    new_hp = [current_hp - damage, 0].max
    @sheet_manager.update_user_hp(defender_id, new_hp)

    # 반격 처리
    counter_damage = 0
    counter_success = false
    if is_counter && damage > 0
      counter_atk = (defender["공격"] || 10).to_i
      counter_roll = rand(1..20)
      counter_total = counter_atk + counter_roll

      # 반격 vs 공격자의 공격력 대항
      if counter_total > atk_total
        counter_success = true
        counter_damage = [counter_total - atk_total, 0].max

        attacker_hp = (attacker["체력"] || "100").to_i
        max_attacker_hp = (attacker["최대체력"] || "100").to_i
        new_attacker_hp = [attacker_hp - counter_damage, 0].max
        @sheet_manager.update_user_hp(attacker_id, new_attacker_hp)
      end
    end

    {
      attacker_name: attacker_name,
      defender_name: defender_name,
      atk_roll: atk_roll,
      atk_total: atk_total,
      def_roll: def_roll,
      def_total: def_total,
      def_bonus: def_bonus,
      is_crit: is_crit,
      is_guarded: is_guarded,
      is_counter: is_counter,
      counter_total: counter_total,
      counter_success: counter_success,
      damage: damage,
      counter_damage: counter_damage,
      defender_hp: new_hp
    }
  end

  def build_attack_message(result, attacker, defender, attacker_id, defender_id)
    message = "#{result[:attacker_name]}의 공격\n"
    message += "공격: #{(attacker["공격"] || 10).to_i} + D20: #{result[:atk_roll]} = #{result[:atk_total]}"
    message += " (크리티컬!)" if result[:is_crit]
    message += "\n\n"

    message += "#{result[:defender_name]}의 방어\n"
    message += "방어: #{(defender["방어"] || 10).to_i} + D20: #{result[:def_roll]} = #{result[:def_total]}"
    if result[:is_guarded]
      message += " + 방어태세: #{result[:def_bonus]} = #{result[:def_total] + result[:def_bonus]}"
    end
    message += "\n\n"

    if result[:damage] > 0
      message += "#{result[:defender_name]}에게 #{result[:damage]} 피해\n"
      message += "남은 HP: #{result[:defender_hp]}"

      if result[:is_counter]
        if result[:counter_success]
          message += "\n\n#{result[:defender_name]}의 반격 성공!\n"
          message += "반격: #{result[:counter_total]} vs 공격: #{result[:atk_total]}\n"
          message += "#{result[:attacker_name]}에게 #{result[:counter_damage]} 피해"
        else
          message += "\n\n#{result[:defender_name]}의 반격 실패!\n"
          message += "반격: #{result[:counter_total]} vs 공격: #{result[:atk_total]}"
        end
      end
    else
      message += "#{result[:defender_name]}이(가) 공격을 완벽히 막아냈습니다!"
    end

    message
  end

  def handle_defeat(battle, defeated_id, status, message)
    defeated_user = @sheet_manager.find_user(defeated_id)
    defeated_name = defeated_user["이름"] || defeated_id

    message += "\n\n━━━━━━━━━━━━━━━━━━\n"
    message += "#{defeated_name}이(가) 쓰러졌습니다.\n"

    team_mode = battle[:team_a].any?

    if team_mode
      defeated_team = battle[:team_a].include?(defeated_id) ? :team_a : :team_b
      team_key = defeated_team
      battle[team_key] = battle[team_key] - [defeated_id]

      if battle[team_key].empty?
        winner_team = defeated_team == :team_a ? :team_b : :team_a
        winner_names = battle[winner_team].map do |id|
          u = @sheet_manager.find_user(id)
          u["이름"] || id
        end

        message += "#{winner_names.join(', ')} 팀 승리!\n"
        message += "━━━━━━━━━━━━━━━━━━"
        BattleState.delete(battle[:battle_id])
      else
        battle[:turn_order].delete(defeated_id)
        battle[:participants].delete(defeated_id)
        next_turn_user = get_next_turn(battle)
        BattleState.update(battle[:battle_id], {
          team_a: battle[:team_a],
          team_b: battle[:team_b],
          turn_order: battle[:turn_order],
          participants: battle[:participants],
          current_turn: next_turn_user,
          guarded: {},
          counter: {}
        })

        next_user_data = @sheet_manager.find_user(next_turn_user)
        next_user_name = next_user_data["이름"] || next_turn_user
        
        message += build_hp_status(battle)
        message += "\n\n#{next_user_name}의 차례\n[공격/@타겟] [방어] [방어/@아군] [반격] [물약사용/크기] [도주]"
      end
    else
      winner_id = battle[:participants].find { |p| p != defeated_id }
      winner = @sheet_manager.find_user(winner_id)
      winner_name = winner["이름"] || winner_id

      message += "#{winner_name} 승리!\n"
      message += "━━━━━━━━━━━━━━━━━━"
      BattleState.delete(battle[:battle_id])
    end

    @mastodon_client.reply_with_mentions(status, message, battle[:participants])
  end

  def get_next_turn(battle)
    current_idx = battle[:turn_order].index(battle[:current_turn])
    next_idx = (current_idx + 1) % battle[:turn_order].length
    battle[:turn_order][next_idx]
  end

  def update_user_items(user_id, items)
    range = '사용자!A:J'
    response = @sheet_manager.instance_variable_get(:@service).get_spreadsheet_values(
      @sheet_manager.instance_variable_get(:@sheet_id),
      range
    )
    return false unless response.values

    response.values.each_with_index do |row, idx|
      next if idx == 0
      if row[0] == user_id
        cell_range = "사용자!I#{idx + 1}"
        value_range = Google::Apis::SheetsV4::ValueRange.new(values: [[items.join(', ')]])
        @sheet_manager.instance_variable_get(:@service).update_spreadsheet_value(
          @sheet_manager.instance_variable_get(:@sheet_id),
          cell_range,
          value_range,
          value_input_option: 'RAW'
        )
        return true
      end
    end
    false
  rescue => e
    puts "[시트 오류] 아이템 업데이트 실패: #{e.message}"
    false
  end
end
