require_relative 'battle_state'

class BattleEngine
  DUMMY_STATS = {
    "하" => { hp: 30, atk: 2, def: 1, agi: 2 },
    "중" => { hp: 50, atk: 3, def: 2, agi: 3 },
    "상" => { hp: 70, atk: 4, def: 3, agi: 4 }
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
    message += "선공: #{first_turn_name}\n"
    message += "━━━━━━━━━━━━━━━━━━\n"
    message += "#{first_turn_name}의 차례\n"
    message += "[공격] [방어] [반격] [물약사용] [도주]"

    # 첫 답글을 원본에 달기
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

    agility_rolls = users.map.with_index { |user, idx| [idx, (user["민첩"] || 10).to_i + rand(1..20)] }
    turn_order_indices = agility_rolls.sort_by { |_, agi| -agi }.map(&:first)
    turn_order = turn_order_indices.map { |i| ids[i] }

    names = users.map { |u| (u && u["이름"]) || "(미등록)" }
    seq_names = turn_order.map { |id| (@sheet_manager.find_user(id) || {})["이름"] || id }
    first_player_name = seq_names.first
    
    message = "━━━━━━━━━━━━━━━━━━\n"
    message += "2:2 전투 시작\n"
    message += "팀1: #{names[0]}, #{names[1]}\n"
    message += "팀2: #{names[2]}, #{names[3]}\n"
    message += "턴 순서: #{seq_names.join(' → ')}\n"
    message += "━━━━━━━━━━━━━━━━━━\n"
    message += "#{first_player_name}의 차례\n"
    message += "[공격] [방어] [반격] [물약사용] [도주]"

    @mastodon_client.reply_with_mentions(reply_status, message, ids)

    BattleState.set({
      type: "2v2",
      participants: ids,
      teams: { team1: [user1_id, user2_id], team2: [user3_id, user4_id] },
      turn_order: turn_order,
      current_turn: turn_order[0],
      guarded: {},
      counter: {},
      last_action_time: Time.now,
      reply_status: reply_status
    })
  end

  # === 허수아비 전투 ===
  def start_dummy_battle(user_id, difficulty, reply_status)
    puts "[DEBUG] Looking for user_id: #{user_id.inspect}"
    user = @sheet_manager.find_user(user_id)
    puts "[DEBUG] Found user: #{user.inspect}"

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
    
    # 상태 먼저 저장
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
      # 허수아비 선공이면 바로 행동 계산
      state = BattleState.get
      atk = DUMMY_STATS[difficulty][:atk]
      atk_roll = rand(1..20)
      atk_total = atk + atk_roll
      
      def_stat = (user["방어"] || 10).to_i
      def_roll = rand(1..20)
      def_total = def_stat + def_roll
      damage = [atk_total - def_total, 0].max
      
      new_hp = [(user["HP"] || 100).to_i - damage, 0].max
      @sheet_manager.update_user(user_id, { hp: new_hp })
      
      # 첫 공격 메시지 포함
      message += "허수아비의 공격 (#{atk_roll}+#{atk}) vs #{user_name}의 방어 (#{def_roll}+#{def_stat})\n"
      message += "데미지: #{damage}, #{user_name} 체력: #{new_hp}\n"
      message += "━━━━━━━━━━━━━━━━━━\n"
      
      if new_hp <= 0
        message += "#{user_name}이(가) 쓰러졌습니다! 허수아비 승리!"
        @mastodon_client.reply_with_mentions(reply_status, message, [user_id])
        BattleState.clear
      else
        # 턴 넘기고 플레이어 차례
        state[:current_turn] = user_id
        message += "#{user_name}의 차례\n"
        message += "[공격] [방어] [반격] [물약사용] [도주]"
        
        @mastodon_client.reply_with_mentions(reply_status, message, [user_id])
      end
    else
      # 플레이어 선공
      message += "#{user_name}의 차례\n"
      message += "[공격] [방어] [반격] [물약사용] [도주]"
      
      @mastodon_client.reply_with_mentions(reply_status, message, [user_id])
    end
  end

  # === 공격 ===
  def attack(user_id)
    state = BattleState.get
    return unless state && state[:current_turn] == user_id

    attacker = @sheet_manager.find_user(user_id)
    return unless attacker

    atk        = (attacker["공격"] || 10).to_i
    atk_roll   = rand(1..20)
    atk_total  = atk + atk_roll
    attacker_name = attacker["이름"] || user_id

    if state[:type] == "dummy"
      # 허수아비 전투
      difficulty = state[:difficulty]
      def_stat   = DUMMY_STATS[difficulty][:def]
      def_roll   = rand(1..20)
      def_total  = def_stat + def_roll
      damage     = [atk_total - def_total, 0].max
      state[:dummy_hp] -= damage

      # 한 툿에 통합
      message = "#{attacker_name}의 공격 (#{atk_roll}+#{atk}) vs 허수아비 방어 (#{def_roll}+#{def_stat})\n"
      message += "데미지: #{damage}, 허수아비 체력: #{state[:dummy_hp]}\n"
      message += "━━━━━━━━━━━━━━━━━━\n"
      
      if state[:dummy_hp] <= 0
        message += "허수아비를 격파했습니다!"
        reply_to_battle_thread(message, state)
        BattleState.clear
      else
        state[:current_turn] = state[:turn_order][(state[:turn_order].index(state[:current_turn]) + 1) % state[:turn_order].length]
        
        # 허수아비 턴이면 바로 행동 계산해서 함께 표시
        if state[:current_turn].to_s.include?("허수아비")
          # 허수아비 행동 계산
          user = @sheet_manager.find_user(user_id)
          atk2 = DUMMY_STATS[difficulty][:atk]
          atk_roll2 = rand(1..20)
          atk_total2 = atk2 + atk_roll2
          
          def_stat2 = (user["방어"] || 10).to_i
          def_roll2 = rand(1..20)
          def_total2 = def_stat2 + def_roll2
          damage2 = [atk_total2 - def_total2, 0].max
          
          guard_text = ""
          if state.dig(:guarded, user_id)
            guard_roll = rand(1..20)
            guard_total = def_stat2 + guard_roll
            
            if guard_total >= atk_total2
              damage2 = 0
              guard_text = "\n방어 성공! (#{guard_roll}+#{def_stat2}=#{guard_total}) 피해 완전 차단!"
            else
              damage2 = atk_total2 - guard_total
              guard_text = "\n방어 실패! (#{guard_roll}+#{def_stat2}=#{guard_total}) 피해: #{damage2}"
            end
            
            state[:guarded].delete(user_id)
          end
          
          counter_happened = false
          if state.dig(:counter, user_id) && damage2 > 0
            state[:counter].delete(user_id)
            state[:dummy_hp] -= 5
            counter_happened = true
            
            if state[:dummy_hp] <= 0
              message += "허수아비의 공격 (#{atk_roll2}+#{atk2}) vs #{attacker_name}의 방어 (#{def_roll2}+#{def_stat2})"
              message += guard_text
              message += "\n반격 발생! 허수아비가 5의 반격 피해를 받음 (허수아비 체력 #{state[:dummy_hp]})\n"
              message += "━━━━━━━━━━━━━━━━━━\n"
              message += "허수아비를 반격으로 격파했습니다!"
              reply_to_battle_thread(message, state)
              BattleState.clear
              return
            end
          end
          
          new_hp = [(user["HP"] || 100).to_i - damage2, 0].max
          @sheet_manager.update_user(user_id, { hp: new_hp })
          
          message += "허수아비의 공격 (#{atk_roll2}+#{atk2}) vs #{attacker_name}의 방어 (#{def_roll2}+#{def_stat2})"
          message += guard_text
          if counter_happened
            message += "\n반격 발생! 허수아비가 5의 반격 피해를 받음 (허수아비 체력 #{state[:dummy_hp]})"
          end
          message += "\n#{attacker_name} 체력: #{new_hp}\n"
          message += "━━━━━━━━━━━━━━━━━━\n"
          
          if new_hp <= 0
            message += "#{attacker_name}이(가) 쓰러졌습니다! 허수아비 승리!"
            reply_to_battle_thread(message, state)
            BattleState.clear
          else
            state[:current_turn] = user_id
            message += "#{attacker_name}의 차례\n"
            message += "[공격] [방어] [반격] [물약사용] [도주]"
            
            reply_to_battle_thread(message, state)
          end
        else
          # 플레이어 차례
          message += "#{attacker_name}의 차례\n"
          message += "[공격] [방어] [반격] [물약사용] [도주]"
          
          reply_to_battle_thread(message, state)
        end
      end
    else
      # 1v1 또는 2v2 전투
      defender_id = find_opponent(user_id, state)
      if defender_id.nil?
        reply_to_battle_thread("공격할 상대가 없습니다. 전투를 종료합니다.", state)
        BattleState.clear
        return
      end

      defender = @sheet_manager.find_user(defender_id)
      if defender.nil?
        reply_to_battle_thread("상대 정보를 찾을 수 없습니다(#{defender_id}). 전투를 종료합니다.", state)
        BattleState.clear
        return
      end

      def_stat  = (defender["방어"] || 10).to_i
      def_roll  = rand(1..20)
      def_total = def_stat + def_roll
      damage    = [atk_total - def_total, 0].max

      # --- 방어/반격 보정 ---
      guard_text = ""
      if state.dig(:guarded, defender_id)
        # 방어 자세였다면 추가 방어 판정
        guard_roll = rand(1..20)
        guard_total = def_stat + guard_roll
        
        if guard_total >= atk_total
          damage = 0
          guard_text = "\n방어 성공! (#{guard_roll}+#{def_stat}=#{guard_total}) 피해 완전 차단!"
        else
          damage = atk_total - guard_total
          guard_text = "\n방어 실패! (#{guard_roll}+#{def_stat}=#{guard_total}) 피해: #{damage}"
        end
        
        state[:guarded].delete(defender_id)
      end

      counter_happened = false
      if state.dig(:counter, defender_id) && damage > 0
        state[:counter].delete(defender_id)
        attacker_new_hp = [(attacker["HP"] || 100).to_i - 5, 0].max
        @sheet_manager.update_user(user_id, { hp: attacker_new_hp })
        counter_happened = true
        
        if attacker_new_hp <= 0
          defender_name = defender["이름"] || defender_id
          message = "#{attacker_name}의 공격 (#{atk_roll}+#{atk}) vs #{defender_name}의 방어 (#{def_roll}+#{def_stat})"
          message += guard_text
          message += "\n반격 발생! #{attacker_name}이(가) 5의 반격 피해를 받음 (체력 #{attacker_new_hp})\n"
          message += "━━━━━━━━━━━━━━━━━━\n"
          message += "#{attacker_name}이(가) 반격으로 쓰러졌습니다! 전투 종료."
          reply_to_battle_thread(message, state)
          BattleState.clear
          return
        end
      end

      new_hp = [(defender["HP"] || 100).to_i - damage, 0].max
      @sheet_manager.update_user(defender_id, { hp: new_hp })

      defender_name = defender["이름"] || defender_id
      
      # 한 툿에 통합
      message = "#{attacker_name}의 공격 (#{atk_roll}+#{atk}) vs #{defender_name}의 방어 (#{def_roll}+#{def_stat})"
      message += guard_text
      if counter_happened
        message += "\n반격 발생! #{attacker_name}이(가) 5의 반격 피해를 받음"
      end
      message += "\n#{defender_name} 체력: #{new_hp}\n"
      message += "━━━━━━━━━━━━━━━━━━\n"

      if new_hp <= 0
        message += "#{defender_name}이(가) 쓰러졌습니다! #{attacker_name} 승리!"
        reply_to_battle_thread(message, state)
        BattleState.clear
      else
        state[:current_turn] = state[:turn_order][(state[:turn_order].index(state[:current_turn]) + 1) % state[:turn_order].length]
        
        # 다음 턴 선택지도 함께 표시
        next_player_id = state[:current_turn]
        next_player = @sheet_manager.find_user(next_player_id)
        next_player_name = next_player ? (next_player["이름"] || next_player_id) : next_player_id
        
        message += "#{next_player_name}의 차례\n"
        message += "[공격] [방어] [반격] [물약사용] [도주]"
        
        reply_to_battle_thread(message, state)
      end
    end
  end

  # === 방어 ===
  def defend(user_id)
    state = BattleState.get
    return unless state && state[:current_turn] == user_id

    state[:guarded] ||= {}
    state[:guarded][user_id] = true

    name = (@sheet_manager.find_user(user_id) || {})["이름"] || user_id
    
    # 한 툿에 통합
    message = "#{name}은(는) 방어 태세!\n(다음 공격 시 방어 주사위 2회 판정)\n"
    message += "━━━━━━━━━━━━━━━━━━\n"

    state[:current_turn] = state[:turn_order][(state[:turn_order].index(state[:current_turn]) + 1) % state[:turn_order].length]
    
    # 다음 턴이 허수아비면 바로 행동 계산
    if state[:current_turn].to_s.include?("허수아비")
      # 허수아비 행동 계산
      difficulty = state[:difficulty]
      user = @sheet_manager.find_user(user_id)
      
      atk = DUMMY_STATS[difficulty][:atk]
      atk_roll = rand(1..20)
      atk_total = atk + atk_roll
      
      def_stat = (user["방어"] || 10).to_i
      def_roll = rand(1..20)
      def_total = def_stat + def_roll
      damage = [atk_total - def_total, 0].max
      
      # 방어 상태 확인
      guard_text = ""
      if state.dig(:guarded, user_id)
        guard_roll = rand(1..20)
        guard_total = def_stat + guard_roll
        
        if guard_total >= atk_total
          damage = 0
          guard_text = "\n방어 성공! (#{guard_roll}+#{def_stat}=#{guard_total}) 피해 완전 차단!"
        else
          damage = atk_total - guard_total
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
          message += "허수아비의 공격 (#{atk_roll}+#{atk}) vs #{name}의 방어 (#{def_roll}+#{def_stat})"
          message += guard_text
          message += "\n반격 발생! 허수아비가 5의 반격 피해를 받음 (허수아비 체력 #{state[:dummy_hp]})\n"
          message += "━━━━━━━━━━━━━━━━━━\n"
          message += "허수아비를 반격으로 격파했습니다!"
          reply_to_battle_thread(message, state)
          BattleState.clear
          return
        end
      end
      
      new_hp = [(user["HP"] || 100).to_i - damage, 0].max
      @sheet_manager.update_user(user_id, { hp: new_hp })
      
      message += "허수아비의 공격 (#{atk_roll}+#{atk}) vs #{name}의 방어 (#{def_roll}+#{def_stat})"
      message += guard_text
      if counter_happened
        message += "\n반격 발생! 허수아비가 5의 반격 피해를 받음 (허수아비 체력 #{state[:dummy_hp]})"
      end
      message += "\n#{name} 체력: #{new_hp}\n"
      message += "━━━━━━━━━━━━━━━━━━\n"
      
      if new_hp <= 0
        message += "#{name}이(가) 쓰러졌습니다! 허수아비 승리!"
        reply_to_battle_thread(message, state)
        BattleState.clear
      else
        state[:current_turn] = user_id
        message += "#{name}의 차례\n"
        message += "[공격] [방어] [반격] [물약사용] [도주]"
        
        reply_to_battle_thread(message, state)
      end
    else
      # 다음 플레이어 선택지도 함께 표시
      next_player = @sheet_manager.find_user(state[:current_turn])
      next_player_name = next_player ? (next_player["이름"] || state[:current_turn]) : state[:current_turn]
      
      message += "#{next_player_name}의 차례\n"
      message += "[공격] [방어] [반격] [물약사용] [도주]"
      
      reply_to_battle_thread(message, state)
    end
  end

  # === 반격 ===
  def counter(user_id)
    state = BattleState.get
    return unless state && state[:current_turn] == user_id

    state[:counter] ||= {}
    state[:counter][user_id] = true

    name = (@sheet_manager.find_user(user_id) || {})["이름"] || user_id
    
    # 한 툿에 통합
    message = "#{name}은(는) 반격 태세!\n(다음 1회 피격 시 상대에게 고정 5 반격)\n"
    message += "━━━━━━━━━━━━━━━━━━\n"

    state[:current_turn] = state[:turn_order][(state[:turn_order].index(state[:current_turn]) + 1) % state[:turn_order].length]
    
    # 다음 턴이 허수아비면 바로 행동 계산
    if state[:current_turn].to_s.include?("허수아비")
      # 허수아비 행동 계산 (방어와 동일)
      difficulty = state[:difficulty]
      user = @sheet_manager.find_user(user_id)
      
      atk = DUMMY_STATS[difficulty][:atk]
      atk_roll = rand(1..20)
      atk_total = atk + atk_roll
      
      def_stat = (user["방어"] || 10).to_i
      def_roll = rand(1..20)
      def_total = def_stat + def_roll
      damage = [atk_total - def_total, 0].max
      
      guard_text = ""
      if state.dig(:guarded, user_id)
        guard_roll = rand(1..20)
        guard_total = def_stat + guard_roll
        
        if guard_total >= atk_total
          damage = 0
          guard_text = "\n방어 성공! (#{guard_roll}+#{def_stat}=#{guard_total}) 피해 완전 차단!"
        else
          damage = atk_total - guard_total
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
          message += "허수아비의 공격 (#{atk_roll}+#{atk}) vs #{name}의 방어 (#{def_roll}+#{def_stat})"
          message += guard_text
          message += "\n반격 발생! 허수아비가 5의 반격 피해를 받음 (허수아비 체력 #{state[:dummy_hp]})\n"
          message += "━━━━━━━━━━━━━━━━━━\n"
          message += "허수아비를 반격으로 격파했습니다!"
          reply_to_battle_thread(message, state)
          BattleState.clear
          return
        end
      end
      
      new_hp = [(user["HP"] || 100).to_i - damage, 0].max
      @sheet_manager.update_user(user_id, { hp: new_hp })
      
      message += "허수아비의 공격 (#{atk_roll}+#{atk}) vs #{name}의 방어 (#{def_roll}+#{def_stat})"
      message += guard_text
      if counter_happened
        message += "\n반격 발생! 허수아비가 5의 반격 피해를 받음 (허수아비 체력 #{state[:dummy_hp]})"
      end
      message += "\n#{name} 체력: #{new_hp}\n"
      message += "━━━━━━━━━━━━━━━━━━\n"
      
      if new_hp <= 0
        message += "#{name}이(가) 쓰러졌습니다! 허수아비 승리!"
        reply_to_battle_thread(message, state)
        BattleState.clear
      else
        state[:current_turn] = user_id
        message += "#{name}의 차례\n"
        message += "[공격] [방어] [반격] [물약사용] [도주]"
        
        reply_to_battle_thread(message, state)
      end
    else
      # 다음 플레이어 선택지도 함께 표시
      next_player = @sheet_manager.find_user(state[:current_turn])
      next_player_name = next_player ? (next_player["이름"] || state[:current_turn]) : state[:current_turn]
      
      message += "#{next_player_name}의 차례\n"
      message += "[공격] [방어] [반격] [물약사용] [도주]"
      
      reply_to_battle_thread(message, state)
    end
  end

  # === 도주 ===
  def flee(user_id)
    puts "[Battle] flee() called by #{user_id}"
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

    name = (@sheet_manager.find_user(user_id) || {})["이름"] || user_id
    
    message = "#{name}이(가) 전투에서 도주했습니다.\n전투 종료"
    
    reply_to_battle_thread(message, state)
    BattleState.clear
  end

  private

  # === 전투 스레드에 답글 (원본에 계속 답글 = 자동 스레드) ===
  def reply_to_battle_thread(message, state)
    return nil unless state[:reply_status]
    participants = state[:participants].reject { |p| p.include?("허수아비") }
    
    # 항상 원본 status에 답글 (마스토돈이 자동으로 스레드 생성)
    @mastodon_client.reply_with_mentions(state[:reply_status], message, participants)
  end

  def find_opponent(user_id, state)
    if state[:type] == "1v1"
      state[:participants].find { |p| p != user_id }
    elsif state[:type] == "2v2"
      my_team   = state[:teams][:team1].include?(user_id) ? :team1 : :team2
      enemy_team = (my_team == :team1 ? :team2 : :team1)
      alive = state[:teams][enemy_team].select do |pid|
        u = @sheet_manager.find_user(pid)
        u && (u["HP"] || 100).to_i > 0
      end
      alive.empty? ? nil : alive.sample
    end
  end
end
