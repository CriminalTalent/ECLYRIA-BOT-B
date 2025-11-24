require_relative 'battle_state'

class BattleEngine
  DUMMY_STATS = {
    "하" => { hp: 30, atk: 2, def: 1, agi: 2, luck: 5 },
    "중" => { hp: 50, atk: 3, def: 2, agi: 3, luck: 8 },
    "상" => { hp: 70, atk: 4, def: 3, agi: 4, luck: 12 }
  }

  def initialize(mastodon_client, sheet_manager)
    @mastodon_client = mastodon_client
    @sheet_manager   = sheet_manager
  end

  # === 1:1 전투 시작 ===
  def start_1v1(user1_id, user2_id, reply_status)
    user1 = @sheet_manager.find_user(user1_id)
    user2 = @sheet_manager.find_user(user2_id)
    unless user1 && user2
      @mastodon_client.reply(reply_status, "참가자 중 등록되지 않은 사용자가 있습니다.")
      return
    end

    agi1 = (user1["민첩"] || 10).to_i + rand(1..20)
    agi2 = (user2["민첩"] || 10).to_i + rand(1..20)
    turn_order = agi1 >= agi2 ? [user1_id, user2_id] : [user2_id, user1_id]

    user1_name = user1["이름"] || user1_id
    user2_name = user2["이름"] || user2_id
    first_turn_name = turn_order[0] == user1_id ? user1_name : user2_name
    
    message = "━━━━━━━━━━━━━━━━━━\n"
    message += "전투 시작: #{user1_name} vs #{user2_name}\n"
    message += "선공: #{first_turn_name} (민첩 #{agi1 >= agi2 ? agi1 : agi2})\n"
    message += "━━━━━━━━━━━━━━━━━━\n"
    message += "#{first_turn_name}의 차례\n"
    message += "[공격] [방어] [반격] [물약사용] [도주]"

    @mastodon_client.reply_with_mentions(reply_status, message, [user1_id, user2_id])
    
    BattleState.set({
      type: "1v1",
      participants: [user1_id, user2_id],
      turn_order: turn_order,
      current_turn: turn_order[0],
      guarded: {},
      counter: {},
      last_action_time: Time.now,
      reply_status: reply_status
    })
  end

  # === 2:2 전투 시작 ===
  def start_2v2(user1_id, user2_id, user3_id, user4_id, reply_status)
    ids   = [user1_id, user2_id, user3_id, user4_id]
    users = ids.map { |id| @sheet_manager.find_user(id) }
    if users.any?(&:nil?)
      @mastodon_client.reply(reply_status, "참가자 중 등록되지 않은 사용자가 있습니다.")
      return
    end

    # 팀별 민첩 합산
    team1_agi = (users[0]["민첩"] || 10).to_i + (users[1]["민첩"] || 10).to_i + rand(1..20)
    team2_agi = (users[2]["민첩"] || 10).to_i + (users[3]["민첩"] || 10).to_i + rand(1..20)
    
    # 팀 내부 턴 순서 (민첩 높은 순)
    team1_order = [0, 1].sort_by { |i| -(users[i]["민첩"] || 10).to_i }.map { |i| ids[i] }
    team2_order = [2, 3].sort_by { |i| -(users[i]["민첩"] || 10).to_i }.map { |i| ids[i] }
    
    # 선공 팀 결정
    if team1_agi >= team2_agi
      first_team = :team1
      turn_order = team1_order + team2_order
    else
      first_team = :team2
      turn_order = team2_order + team1_order
    end

    names = users.map { |u| (u && u["이름"]) || "(미등록)" }
    first_team_name = first_team == :team1 ? "팀1" : "팀2"
    
    message = "━━━━━━━━━━━━━━━━━━\n"
    message += "2:2 팀 전투 시작\n"
    message += "팀1: #{names[0]}, #{names[1]}\n"
    message += "팀2: #{names[2]}, #{names[3]}\n"
    message += "선공 판정: 팀1(#{team1_agi}) vs 팀2(#{team2_agi})\n"
    message += "선공: #{first_team_name}\n"
    message += "━━━━━━━━━━━━━━━━━━\n"
    message += "라운드 1 시작\n"
    
    # 첫 번째 플레이어
    first_player = @sheet_manager.find_user(turn_order[0])
    first_player_name = first_player["이름"] || turn_order[0]
    message += "#{first_player_name}의 차례\n"
    message += "[공격/@타겟] [방어] [반격] [물약사용] [도주]"

    @mastodon_client.reply_with_mentions(reply_status, message, ids)

    BattleState.set({
      type: "2v2",
      participants: ids,
      teams: { team1: [user1_id, user2_id], team2: [user3_id, user4_id] },
      turn_order: turn_order,
      current_turn: turn_order[0],
      round: 1,
      turn_index: 0,
      actions_queue: [],  # 행동 큐
      guarded: {},
      counter: {},
      last_action_time: Time.now,
      reply_status: reply_status
    })
  end

  # === 허수아비 전투 ===
  def start_dummy_battle(user_id, difficulty, reply_status)
    user = @sheet_manager.find_user(user_id)
    unless user
      @mastodon_client.reply(reply_status, "등록되지 않은 사용자입니다.")
      return
    end

    dummy_id   = "허수아비_#{difficulty}"
    user_agi   = (user["민첩"] || 10).to_i + rand(1..20)
    dummy_agi  = DUMMY_STATS[difficulty][:agi] + rand(1..20)
    turn_order = user_agi >= dummy_agi ? [user_id, dummy_id] : [dummy_id, user_id]

    user_name = user["이름"] || user_id
    first_turn_name = turn_order[0] == user_id ? user_name : '허수아비'
    
    message = "━━━━━━━━━━━━━━━━━━\n"
    message += "허수아비(#{difficulty}) 전투 시작\n"
    message += "선공: #{first_turn_name}\n"
    message += "━━━━━━━━━━━━━━━━━━\n"
    
    BattleState.set({
      type: "dummy",
      difficulty: difficulty,
      participants: [user_id, dummy_id],
      turn_order: turn_order,
      current_turn: turn_order[0],
      guarded: {},
      counter: {},
      dummy_hp: DUMMY_STATS[difficulty][:hp],
      last_action_time: Time.now,
      reply_status: reply_status
    })
    
    if turn_order[0] == dummy_id
      state = BattleState.get
      perform_dummy_attack(user_id, user, difficulty, state, message)
    else
      message += "#{user_name}의 차례\n"
      message += "[공격] [방어] [반격] [물약사용] [도주]"
      @mastodon_client.reply_with_mentions(reply_status, message, [user_id])
    end
  end

  # === 공격 (타겟 지정 가능) ===
  def attack(user_id, target_id = nil)
    state = BattleState.get
    return unless state && state[:current_turn] == user_id

    attacker = @sheet_manager.find_user(user_id)
    return unless attacker

    if state[:type] == "2v2"
      # 2:2 전투는 행동 큐에 추가
      handle_2v2_action(user_id, :attack, target_id, state)
    elsif state[:type] == "dummy"
      perform_player_attack_on_dummy(user_id, attacker, state)
    else
      # 1:1 전투
      target_id ||= find_opponent(user_id, state)
      perform_player_attack(user_id, attacker, target_id, state)
    end
  end

  # === 방어 ===
  def defend(user_id)
    state = BattleState.get
    return unless state && state[:current_turn] == user_id

    if state[:type] == "2v2"
      # 2:2 전투는 행동 큐에 추가
      handle_2v2_action(user_id, :defend, nil, state)
      return
    end

    state[:guarded] ||= {}
    state[:guarded][user_id] = true

    name = (@sheet_manager.find_user(user_id) || {})["이름"] || user_id
    
    message = "#{name}은(는) 방어 태세!\n"
    message += "(다음 공격 시 방어 주사위 2회 판정)\n"
    message += "━━━━━━━━━━━━━━━━━━\n"

    state[:current_turn] = state[:turn_order][(state[:turn_order].index(state[:current_turn]) + 1) % state[:turn_order].length]
    
    if state[:current_turn].to_s.include?("허수아비")
      difficulty = state[:difficulty]
      user = @sheet_manager.find_user(user_id)
      perform_dummy_attack(user_id, user, difficulty, state, message)
    else
      next_player = @sheet_manager.find_user(state[:current_turn])
      next_player_name = next_player ? (next_player["이름"] || state[:current_turn]) : state[:current_turn]
      
      message += "#{next_player_name}의 차례\n"
      message += get_action_options(state)
      
      reply_to_battle_thread(message, state)
    end
  end

  # === 반격 ===
  def counter(user_id)
    state = BattleState.get
    return unless state && state[:current_turn] == user_id

    if state[:type] == "2v2"
      # 2:2 전투는 행동 큐에 추가
      handle_2v2_action(user_id, :counter, nil, state)
      return
    end

    state[:counter] ||= {}
    state[:counter][user_id] = true

    name = (@sheet_manager.find_user(user_id) || {})["이름"] || user_id
    
    message = "#{name}은(는) 반격 태세!\n"
    message += "(다음 1회 피격 시 상대에게 고정 5 반격)\n"
    message += "━━━━━━━━━━━━━━━━━━\n"

    state[:current_turn] = state[:turn_order][(state[:turn_order].index(state[:current_turn]) + 1) % state[:turn_order].length]
    
    if state[:current_turn].to_s.include?("허수아비")
      difficulty = state[:difficulty]
      user = @sheet_manager.find_user(user_id)
      perform_dummy_attack(user_id, user, difficulty, state, message)
    else
      next_player = @sheet_manager.find_user(state[:current_turn])
      next_player_name = next_player ? (next_player["이름"] || state[:current_turn]) : state[:current_turn]
      
      message += "#{next_player_name}의 차례\n"
      message += get_action_options(state)
      
      reply_to_battle_thread(message, state)
    end
  end

  # === 도주 ===
  def flee(user_id)
    state = BattleState.get
    unless state
      name = (@sheet_manager.find_user(user_id) || {})["이름"] || user_id
      @mastodon_client.post("#{name}은(는) 현재 전투 중이 아닙니다.", visibility: 'public')
      return
    end

    unless state[:participants].include?(user_id)
      name = (@sheet_manager.find_user(user_id) || {})["이름"] || user_id
      @mastodon_client.post("#{name}은(는) 이 전투의 참가자가 아닙니다.", visibility: 'public')
      return
    end

    user = @sheet_manager.find_user(user_id)
    name = (user || {})["이름"] || user_id
    luck = (user["행운"] || 10).to_i
    agility = (user["민첩"] || 10).to_i
    
    # 행운 + 민첩 기반 도주 판정
    flee_roll = rand(1..20)
    flee_total = flee_roll + luck + agility
    flee_difficulty = 25  # 기본 난이도
    
    if flee_total >= flee_difficulty
      message = "#{name}이(가) 전투에서 도주했습니다!\n"
      message += "판정: #{flee_roll} + 행운 #{luck} + 민첩 #{agility} = #{flee_total} (난이도 #{flee_difficulty})\n"
      message += "전투 종료"
      
      reply_to_battle_thread(message, state)
      BattleState.clear
    else
      message = "#{name}의 도주 실패!\n"
      message += "판정: #{flee_roll} + 행운 #{luck} + 민첩 #{agility} = #{flee_total} (난이도 #{flee_difficulty})\n"
      message += "턴을 소비했습니다.\n"
      message += "━━━━━━━━━━━━━━━━━━\n"
      
      state[:current_turn] = state[:turn_order][(state[:turn_order].index(state[:current_turn]) + 1) % state[:turn_order].length]
      
      if state[:current_turn].to_s.include?("허수아비")
        difficulty = state[:difficulty]
        perform_dummy_attack(user_id, user, difficulty, state, message)
      else
        next_player = @sheet_manager.find_user(state[:current_turn])
        next_player_name = next_player ? (next_player["이름"] || state[:current_turn]) : state[:current_turn]
        
        message += "#{next_player_name}의 차례\n"
        message += get_action_options(state)
        
        reply_to_battle_thread(message, state)
      end
    end
  end

  private

  # === 2:2 행동 처리 ===
  def handle_2v2_action(user_id, action_type, target_id, state)
    # 타겟 검증 (공격일 경우)
    if action_type == :attack
      if target_id
        unless state[:participants].include?(target_id)
          reply_to_battle_thread("잘못된 타겟입니다.", state)
          return
        end
        
        my_team = state[:teams][:team1].include?(user_id) ? :team1 : :team2
        if state[:teams][my_team].include?(target_id)
          reply_to_battle_thread("아군을 공격할 수 없습니다!", state)
          return
        end
      else
        # 타겟 자동 선택
        target_id = find_opponent(user_id, state)
      end
    end

    # 행동 큐에 추가
    state[:actions_queue] ||= []
    state[:actions_queue] << {
      user_id: user_id,
      action: action_type,
      target: target_id
    }

    user = @sheet_manager.find_user(user_id)
    user_name = user["이름"] || user_id
    
    # 행동 확인 메시지
    action_text = case action_type
                  when :attack
                    target_name = (@sheet_manager.find_user(target_id) || {})["이름"] || target_id
                    "#{user_name}이(가) #{target_name}을(를) 공격 준비"
                  when :defend
                    "#{user_name}이(가) 방어 태세"
                  when :counter
                    "#{user_name}이(가) 반격 태세"
                  end
    
    message = "#{action_text}\n"
    message += "━━━━━━━━━━━━━━━━━━\n"

    # 턴 진행
    state[:turn_index] += 1
    
    # 모든 플레이어가 행동했는지 확인
    if state[:turn_index] >= 4
      # 라운드 종료 - 결과 일괄 처리
      process_2v2_round(state, message)
    else
      # 다음 플레이어 턴
      state[:current_turn] = state[:turn_order][state[:turn_index]]
      next_player = @sheet_manager.find_user(state[:current_turn])
      next_player_name = next_player["이름"] || state[:current_turn]
      
      message += "#{next_player_name}의 차례\n"
      message += "[공격/@타겟] [방어] [반격] [물약사용] [도주]"
      
      reply_to_battle_thread(message, state)
    end
  end

  # === 2:2 라운드 결과 처리 ===
  def process_2v2_round(state, prefix_message)
    message = prefix_message
    message += "\n라운드 #{state[:round]} 결과\n"
    message += "━━━━━━━━━━━━━━━━━━\n\n"

    # 방어/반격 태세 먼저 적용
    state[:actions_queue].each do |action|
      if action[:action] == :defend
        state[:guarded] ||= {}
        state[:guarded][action[:user_id]] = true
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
      
      result = calculate_attack_result(attacker, action[:user_id], defender, action[:target], state)
      message += result[:message] + "\n"
      
      # HP 업데이트
      if result[:damage] > 0
        new_hp = [(defender["HP"] || 100).to_i - result[:damage], 0].max
        @sheet_manager.update_user(action[:target], { hp: new_hp })
      end
      
      # 반격 처리
      if result[:counter_damage] > 0
        attacker_new_hp = [(attacker["HP"] || 100).to_i - result[:counter_damage], 0].max
        @sheet_manager.update_user(action[:user_id], { hp: attacker_new_hp })
      end
    end

    message += "━━━━━━━━━━━━━━━━━━\n"

    # 승패 확인
    team1_alive = state[:teams][:team1].count do |pid|
      u = @sheet_manager.find_user(pid)
      u && (u["HP"] || 0).to_i > 0
    end
    
    team2_alive = state[:teams][:team2].count do |pid|
      u = @sheet_manager.find_user(pid)
      u && (u["HP"] || 0).to_i > 0
    end

    if team1_alive == 0
      message += "팀2 승리!"
      reply_to_battle_thread(message, state)
      BattleState.clear
      return
    elsif team2_alive == 0
      message += "팀1 승리!"
      reply_to_battle_thread(message, state)
      BattleState.clear
      return
    end

    # 다음 라운드 준비
    state[:round] += 1
    state[:turn_index] = 0
    state[:actions_queue] = []
    state[:guarded] = {}
    state[:counter] = {}
    state[:current_turn] = state[:turn_order][0]

    first_player = @sheet_manager.find_user(state[:current_turn])
    first_player_name = first_player["이름"] || state[:current_turn]
    
    message += "\n라운드 #{state[:round]} 시작\n"
    message += "#{first_player_name}의 차례\n"
    message += "[공격/@타겟] [방어] [반격] [물약사용] [도주]"

    reply_to_battle_thread(message, state)
  end

  # === 공격 결과 계산 (2:2용) ===
  def calculate_attack_result(attacker, attacker_id, defender, defender_id, state)
    attacker_name = attacker["이름"] || attacker_id
    defender_name = defender["이름"] || defender_id
    
    atk = (attacker["공격"] || 10).to_i
    atk_roll = rand(1..20)
    luck = (attacker["행운"] || 10).to_i
    
    crit_result = check_critical_hit(luck)
    atk_total = atk + atk_roll
    
    def_stat = (defender["방어"] || 10).to_i
    def_roll = rand(1..20)
    def_total = def_stat + def_roll
    damage = [atk_total - def_total, 0].max
    
    if crit_result[:is_crit]
      damage = (damage * 1.5).to_i
    end

    guard_text = ""
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
    
    current_hp = (defender["HP"] || 100).to_i
    new_hp = [current_hp - damage, 0].max
    message += " (#{defender_name} #{new_hp}/100)"

    {
      message: message,
      damage: damage,
      counter_damage: counter_damage
    }
  end

  # === 치명타 판정 ===
  def check_critical_hit(luck)
    # 행운 10당 5% 치명타 확률
    crit_chance = [luck / 2, 50].min  # 최대 50%
    roll = rand(1..100)
    
    if roll <= crit_chance
      return { is_crit: true, roll: roll, chance: crit_chance }
    else
      return { is_crit: false, roll: roll, chance: crit_chance }
    end
  end

  # === 플레이어의 플레이어 공격 ===
  def perform_player_attack(attacker_id, attacker, defender_id, state)
    defender = @sheet_manager.find_user(defender_id)
    if defender.nil?
      reply_to_battle_thread("상대 정보를 찾을 수 없습니다. 전투를 종료합니다.", state)
      BattleState.clear
      return
    end

    attacker_name = attacker["이름"] || attacker_id
    defender_name = defender["이름"] || defender_id
    
    atk = (attacker["공격"] || 10).to_i
    atk_roll = rand(1..20)
    luck = (attacker["행운"] || 10).to_i
    
    # 치명타 판정
    crit_result = check_critical_hit(luck)
    
    atk_total = atk + atk_roll
    
    def_stat = (defender["방어"] || 10).to_i
    def_roll = rand(1..20)
    def_total = def_stat + def_roll
    damage = [atk_total - def_total, 0].max
    
    # 치명타 시 데미지 1.5배
    if crit_result[:is_crit]
      damage = (damage * 1.5).to_i
    end

    guard_text = ""
    if state.dig(:guarded, defender_id)
      guard_roll = rand(1..20)
      guard_total = def_stat + guard_roll
      
      if guard_total >= atk_total
        damage = 0
        guard_text = "\n방어 성공! (#{guard_roll}+#{def_stat}=#{guard_total}) 피해 완전 차단!"
      else
        damage = atk_total - guard_total
        if crit_result[:is_crit]
          damage = (damage * 1.5).to_i
        end
        guard_text = "\n방어 실패! (#{guard_roll}+#{def_stat}=#{guard_total}) 피해: #{damage}"
      end
      
      state[:guarded].delete(defender_id)
    end

    counter_happened = false
    if state.dig(:counter, defender_id) && damage > 0
      state[:counter].delete(defender_id)
      attacker_new_hp = [(attacker["HP"] || 100).to_i - 5, 0].max
      @sheet_manager.update_user(attacker_id, { hp: attacker_new_hp })
      counter_happened = true
      
      if attacker_new_hp <= 0
        message = "#{attacker_name}의 공격 (#{atk_roll}+#{atk})"
        message += crit_result[:is_crit] ? " [치명타!]" : ""
        message += " vs #{defender_name}의 방어 (#{def_roll}+#{def_stat})"
        message += guard_text
        message += "\n반격 발생! #{attacker_name}이(가) 5의 반격 피해 (체력 #{attacker_new_hp})\n"
        message += "━━━━━━━━━━━━━━━━━━\n"
        message += "#{attacker_name}이(가) 반격으로 쓰러졌습니다! 전투 종료."
        reply_to_battle_thread(message, state)
        BattleState.clear
        return
      end
    end

    new_hp = [(defender["HP"] || 100).to_i - damage, 0].max
    @sheet_manager.update_user(defender_id, { hp: new_hp })
    
    message = "#{attacker_name}의 공격 (#{atk_roll}+#{atk})"
    
    if crit_result[:is_crit]
      message += " [치명타!] (행운 #{luck}, 확률 #{crit_result[:chance]}%)"
    end
    
    message += " vs #{defender_name}의 방어 (#{def_roll}+#{def_stat})"
    message += guard_text
    
    if counter_happened
      message += "\n반격 발생! #{attacker_name}이(가) 5의 반격 피해"
    end
    
    message += "\n데미지: #{damage}\n"
    message += "#{defender_name} 체력: #{new_hp}\n"
    message += "━━━━━━━━━━━━━━━━━━\n"

    if new_hp <= 0
      message += "#{defender_name}이(가) 쓰러졌습니다! #{attacker_name} 승리!"
      reply_to_battle_thread(message, state)
      BattleState.clear
    else
      state[:current_turn] = state[:turn_order][(state[:turn_order].index(state[:current_turn]) + 1) % state[:turn_order].length]
      
      next_player_id = state[:current_turn]
      next_player = @sheet_manager.find_user(next_player_id)
      next_player_name = next_player ? (next_player["이름"] || next_player_id) : next_player_id
      
      message += "#{next_player_name}의 차례\n"
      message += get_action_options(state)
      
      reply_to_battle_thread(message, state)
    end
  end

  # === 플레이어의 허수아비 공격 ===
  def perform_player_attack_on_dummy(user_id, attacker, state)
    difficulty = state[:difficulty]
    attacker_name = attacker["이름"] || user_id
    
    atk = (attacker["공격"] || 10).to_i
    atk_roll = rand(1..20)
    luck = (attacker["행운"] || 10).to_i
    
    # 치명타 판정
    crit_result = check_critical_hit(luck)
    
    atk_total = atk + atk_roll
    
    def_stat = DUMMY_STATS[difficulty][:def]
    def_roll = rand(1..20)
    def_total = def_stat + def_roll
    damage = [atk_total - def_total, 0].max
    
    # 치명타 시 데미지 1.5배
    if crit_result[:is_crit]
      damage = (damage * 1.5).to_i
    end
    
    state[:dummy_hp] -= damage

    message = "#{attacker_name}의 공격 (#{atk_roll}+#{atk})"
    
    if crit_result[:is_crit]
      message += " [치명타!] (행운 #{luck}, 확률 #{crit_result[:chance]}%)"
    end
    
    message += " vs 허수아비 방어 (#{def_roll}+#{def_stat})\n"
    message += "데미지: #{damage}\n"
    message += "허수아비 체력: #{state[:dummy_hp]}\n"
    message += "━━━━━━━━━━━━━━━━━━\n"
    
    if state[:dummy_hp] <= 0
      message += "허수아비를 격파했습니다!"
      reply_to_battle_thread(message, state)
      BattleState.clear
    else
      state[:current_turn] = state[:turn_order][(state[:turn_order].index(state[:current_turn]) + 1) % state[:turn_order].length]
      
      if state[:current_turn].to_s.include?("허수아비")
        user = @sheet_manager.find_user(user_id)
        perform_dummy_attack(user_id, user, difficulty, state, message)
      else
        message += "#{attacker_name}의 차례\n"
        message += "[공격] [방어] [반격] [물약사용] [도주]"
        
        reply_to_battle_thread(message, state)
      end
    end
  end

  # === 허수아비의 공격 ===
  def perform_dummy_attack(user_id, user, difficulty, state, prefix_message = "")
    user_name = user["이름"] || user_id
    
    atk = DUMMY_STATS[difficulty][:atk]
    atk_roll = rand(1..20)
    dummy_luck = DUMMY_STATS[difficulty][:luck]
    
    # 허수아비도 치명타 가능
    crit_result = check_critical_hit(dummy_luck)
    
    atk_total = atk + atk_roll
    
    def_stat = (user["방어"] || 10).to_i
    def_roll = rand(1..20)
    def_total = def_stat + def_roll
    damage = [atk_total - def_total, 0].max
    
    # 치명타 시 데미지 1.5배
    if crit_result[:is_crit]
      damage = (damage * 1.5).to_i
    end
    
    guard_text = ""
    if state.dig(:guarded, user_id)
      guard_roll = rand(1..20)
      guard_total = def_stat + guard_roll
      
      if guard_total >= atk_total
        damage = 0
        guard_text = "\n방어 성공! (#{guard_roll}+#{def_stat}=#{guard_total}) 피해 완전 차단!"
      else
        damage = atk_total - guard_total
        if crit_result[:is_crit]
          damage = (damage * 1.5).to_i
        end
        guard_text = "\n방어 실패! (#{guard_roll}+#{def_stat}=#{guard_total}) 피해: #{damage}"
      end
      
      state[:guarded].delete(user_id)
    end
    
    counter_happened = false
    if state.dig(:counter, user_id) && damage > 0
      state[:counter].delete(user_id)
      state[:dummy_hp] -= 5
      counter_happened = true
      
      if state[:dummy_hp] <= 0
        message = prefix_message
        message += "허수아비의 공격 (#{atk_roll}+#{atk})"
        message += crit_result[:is_crit] ? " [치명타!]" : ""
        message += " vs #{user_name}의 방어 (#{def_roll}+#{def_stat})"
        message += guard_text
        message += "\n반격 발생! 허수아비가 5의 반격 피해 (허수아비 체력 #{state[:dummy_hp]})\n"
        message += "━━━━━━━━━━━━━━━━━━\n"
        message += "허수아비를 반격으로 격파했습니다!"
        reply_to_battle_thread(message, state)
        BattleState.clear
        return
      end
    end
    
    new_hp = [(user["HP"] || 100).to_i - damage, 0].max
    @sheet_manager.update_user(user_id, { hp: new_hp })
    
    message = prefix_message
    message += "허수아비의 공격 (#{atk_roll}+#{atk})"
    
    if crit_result[:is_crit]
      message += " [치명타!]"
    end
    
    message += " vs #{user_name}의 방어 (#{def_roll}+#{def_stat})"
    message += guard_text
    
    if counter_happened
      message += "\n반격 발생! 허수아비가 5의 반격 피해 (허수아비 체력 #{state[:dummy_hp]})"
    end
    
    message += "\n데미지: #{damage}\n"
    message += "#{user_name} 체력: #{new_hp}\n"
    message += "━━━━━━━━━━━━━━━━━━\n"
    
    if new_hp <= 0
      message += "#{user_name}이(가) 쓰러졌습니다! 허수아비 승리!"
      reply_to_battle_thread(message, state)
      BattleState.clear
    else
      state[:current_turn] = user_id
      message += "#{user_name}의 차례\n"
      message += "[공격] [방어] [반격] [물약사용] [도주]"
      
      reply_to_battle_thread(message, state)
    end
  end

  # === 행동 옵션 표시 ===
  def get_action_options(state)
    if state[:type] == "2v2"
      my_team = state[:teams][:team1].include?(state[:current_turn]) ? :team1 : :team2
      enemy_team = my_team == :team1 ? :team2 : :team1
      enemies = state[:teams][enemy_team].select do |pid|
        u = @sheet_manager.find_user(pid)
        u && (u["HP"] || 100).to_i > 0
      end
      
      options = "[공격/@타겟] [방어] [반격] [물약사용] [도주]\n"
      options += "타겟: " + enemies.map { |e| "@#{e}" }.join(", ")
      return options
    else
      return "[공격] [방어] [반격] [물약사용] [도주]"
    end
  end

  # === 전투 스레드에 답글 ===
  def reply_to_battle_thread(message, state)
    return nil unless state[:reply_status]
    participants = state[:participants].reject { |p| p.include?("허수아비") }
    @mastodon_client.reply_with_mentions(state[:reply_status], message, participants)
  end

  # === 상대 찾기 ===
  def find_opponent(user_id, state)
    if state[:type] == "1v1"
      state[:participants].find { |p| p != user_id }
    elsif state[:type] == "2v2"
      my_team = state[:teams][:team1].include?(user_id) ? :team1 : :team2
      enemy_team = (my_team == :team1 ? :team2 : :team1)
      alive = state[:teams][enemy_team].select do |pid|
        u = @sheet_manager.find_user(pid)
        u && (u["HP"] || 100).to_i > 0
      end
      alive.empty? ? nil : alive.sample
    end
  end
end
