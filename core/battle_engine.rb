require_relative 'battle_state'

class BattleEngine
  DUMMY_STATS = {
    "하" => { hp: 60, atk: 8,  def: 6,  agi: 8  },
    "중" => { hp: 80, atk: 12, def: 10, agi: 12 },
    "상" => { hp: 100, atk: 16, def: 14, agi: 16 }
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

    BattleState.set({
      type: "1v1",
      participants: [user1_id, user2_id],
      turn_order: turn_order,
      current_turn: turn_order[0],
      guarded: {},
      counter: {},
      last_action_time: Time.now,
      reply_status: reply_status  # 원본 멘션 저장
    })

    user1_name = user1["이름"] || user1_id
    user2_name = user2["이름"] || user2_id
    message = "전투 시작: #{user1_name} vs #{user2_name}\n선공: #{turn_order[0] == user1_id ? user1_name : user2_name}"
    
    @mastodon_client.reply_with_mentions(reply_status, message, [user1_id, user2_id])
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

    BattleState.set({
      type: "2v2",
      participants: ids,
      teams: { team1: [user1_id, user2_id], team2: [user3_id, user4_id] },
      turn_order: turn_order,
      current_turn: turn_order[0],
      guarded: {},
      counter: {},
      last_action_time: Time.now,
      reply_status: reply_status  # 원본 멘션 저장
    })

    names = users.map { |u| (u && u["이름"]) || "(미등록)" }
    seq_names = turn_order.map { |id| (@sheet_manager.find_user(id) || {})["이름"] || id }
    message = "2:2 전투 시작\n팀1: #{names[0]}, #{names[1]}\n팀2: #{names[2]}, #{names[3]}\n턴 순서: #{seq_names.join(' → ')}"
    
    @mastodon_client.reply_with_mentions(reply_status, message, ids)
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
      reply_status: reply_status  # 원본 멘션 저장
    })

    user_name = user["이름"] || user_id
    message = "허수아비(#{difficulty}) 전투 시작\n선공: #{turn_order[0] == user_id ? user_name : '허수아비'}"
    
    @mastodon_client.reply_with_mentions(reply_status, message, [user_id])

    dummy_turn if turn_order[0] != user_id
  end

  # === 공격 ===
  def attack(user_id)
    state = BattleState.get
    return unless state && state[:current_turn] == user_id

    attacker = @sheet_manager.find_user(user_id)
    return unless attacker

    atk        = (attacker["공격력"] || 10).to_i
    atk_roll   = rand(1..20)
    atk_total  = atk + atk_roll
    attacker_name = attacker["이름"] || user_id

    if state[:type] == "dummy"
      difficulty = state[:difficulty]
      def_stat   = DUMMY_STATS[difficulty][:def]
      def_roll   = rand(1..20)
      def_total  = def_stat + def_roll
      damage     = [atk_total - def_total, 0].max

      state[:dummy_hp] -= damage

      message = "#{attacker_name}의 공격 (#{atk_roll}+#{atk}) vs 허수아비 방어 (#{def_roll}+#{def_stat})\n" \
                "데미지: #{damage}, 허수아비 체력: #{state[:dummy_hp]}"
      
      reply_to_battle(message, state)

      if state[:dummy_hp] <= 0
        reply_to_battle("허수아비를 격파했습니다!", state)
        BattleState.clear
      else
        BattleState.next_turn
        dummy_turn
      end
    else
      defender_id = find_opponent(user_id, state)
      if defender_id.nil?
        reply_to_battle("공격할 상대가 없습니다. 전투를 종료합니다.", state)
        BattleState.clear
        return
      end

      defender = @sheet_manager.find_user(defender_id)
      if defender.nil?
        reply_to_battle("상대 정보를 찾을 수 없습니다(#{defender_id}). 전투를 종료합니다.", state)
        BattleState.clear
        return
      end

      def_stat  = (defender["방어력"] || 10).to_i
      def_roll  = rand(1..20)
      def_total = def_stat + def_roll
      damage    = [atk_total - def_total, 0].max

      # --- 방어/반격 보정 ---
      if state.dig(:guarded, defender_id)
        damage = (damage * 0.5).ceil
        state[:guarded].delete(defender_id)
      end
      if state.dig(:counter, defender_id) && damage > 0
        state[:counter].delete(defender_id)
        attacker_rec   = attacker
        attacker_new_hp = [(attacker_rec["HP"] || 100).to_i - 5, 0].max
        @sheet_manager.update_stat(user_id, "HP", attacker_new_hp, :set)
        
        reply_to_battle("반격 발생! #{attacker_name}이(가) 5의 반격 피해를 받음 (체력 #{attacker_new_hp})", state)
        
        if attacker_new_hp <= 0
          reply_to_battle("#{attacker_name}이(가) 반격으로 쓰러졌습니다! 전투 종료.", state)
          BattleState.clear
          return
        end
      end

      new_hp = [(defender["HP"] || 100).to_i - damage, 0].max
      @sheet_manager.update_stat(defender_id, "HP", new_hp, :set)

      defender_name = defender["이름"] || defender_id
      message = "#{attacker_name}의 공격 (#{atk_roll}+#{atk}) vs #{defender_name}의 방어 (#{def_roll}+#{def_stat})\n" \
                "데미지: #{damage}, #{defender_name} 체력: #{new_hp}"
      
      reply_to_battle(message, state)

      if new_hp <= 0
        reply_to_battle("#{defender_name}이(가) 쓰러졌습니다! #{attacker_name} 승리!", state)
        BattleState.clear
      else
        BattleState.next_turn
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
    reply_to_battle("#{name}은(는) 방어 태세! (다음 1회 받는 피해 50% 감소)", state)

    BattleState.next_turn
  end

  # === 반격 ===
  def counter(user_id)
    state = BattleState.get
    return unless state && state[:current_turn] == user_id

    state[:counter] ||= {}
    state[:counter][user_id] = true

    name = (@sheet_manager.find_user(user_id) || {})["이름"] || user_id
    reply_to_battle("#{name}은(는) 반격 태세! (다음 1회 피격 시 상대에게 고정 5 반격)", state)

    BattleState.next_turn
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
    reply_to_battle("#{name}이(가) 전투에서 도주했습니다. 전투 종료.", state)
    BattleState.clear
  end


  private

  # === 전투 스레드에 답글 (참여자 멘션) ===
  def reply_to_battle(message, state)
    return unless state[:reply_status]
    
    participants = state[:participants].reject { |p| p.include?("허수아비") }
    @mastodon_client.reply_with_mentions(state[:reply_status], message, participants)
  end

  # === 허수아비 행동 ===
  def dummy_turn
    state = BattleState.get
    return unless state && state[:current_turn].to_s.include?("허수아비")

    difficulty = state[:difficulty]
    user_id    = state[:participants].find { |p| !p.include?("허수아비") }
    user       = @sheet_manager.find_user(user_id)
    return unless user
    user_name  = user["이름"] || user_id

    atk       = DUMMY_STATS[difficulty][:atk]
    atk_roll  = rand(1..20)
    atk_total = atk + atk_roll
    def_stat  = (user["방어력"] || 10).to_i
    def_roll  = rand(1..20)
    def_total = def_stat + def_roll

    damage = [atk_total - def_total, 0].max

    # --- 방어/반격 보정 ---
    if state.dig(:guarded, user_id)
      damage = (damage * 0.5).ceil
      state[:guarded].delete(user_id)
    end
    if state.dig(:counter, user_id) && damage > 0
      state[:counter].delete(user_id)
      state[:dummy_hp] -= 5
      reply_to_battle("반격 발생! 허수아비가 5의 반격 피해를 받음 (허수아비 체력 #{state[:dummy_hp]})", state)
      
      if state[:dummy_hp] <= 0
        reply_to_battle("허수아비를 반격으로 격파했습니다!", state)
        BattleState.clear
        return
      end
    end

    new_hp = [(user["HP"] || 100).to_i - damage, 0].max
    @sheet_manager.update_stat(user_id, "HP", new_hp, :set)

    message = "허수아비의 공격 (#{atk_roll}+#{atk}) vs #{user_name}의 방어 (#{def_roll}+#{def_stat})\n" \
              "데미지: #{damage}, #{user_name} 체력: #{new_hp}"
    
    reply_to_battle(message, state)

    if new_hp <= 0
      reply_to_battle("#{user_name}이(가) 쓰러졌습니다! 허수아비 승리!", state)
      BattleState.clear
    else
      BattleState.next_turn
    end
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
