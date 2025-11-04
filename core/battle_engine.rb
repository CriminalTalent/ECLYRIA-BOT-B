require_relative 'battle_state'

class BattleEngine
  DUMMY_STATS = {
    "하" => { hp: 60, atk: 8, def: 6, agi: 8 },
    "중" => { hp: 80, atk: 12, def: 10, agi: 12 },
    "상" => { hp: 100, atk: 16, def: 14, agi: 16 }
  }

  # ✅ 생성자 추가 (ArgumentError 방지)
  def initialize(mastodon_client, sheet_manager)
    @mastodon_client = mastodon_client
    @sheet_manager = sheet_manager
  end

  # === 1:1 전투 시작 ===
  def start_1v1(user1_id, user2_id, reply_id)
    user1 = @sheet_manager.find_user(user1_id)
    user2 = @sheet_manager.find_user(user2_id)

    unless user1 && user2
      @mastodon_client.reply(reply_id, "참가자 중 등록되지 않은 사용자가 있습니다.", visibility: 'public')
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
      last_action_time: Time.now
    })

    user1_name = user1["이름"] || user1_id
    user2_name = user2["이름"] || user2_id
    message = "전투 시작: #{user1_name} vs #{user2_name}\n선공: #{turn_order[0] == user1_id ? user1_name : user2_name}"

    @mastodon_client.post(message, visibility: 'public')
    [user1_id, user2_id].each { |p_id| @mastodon_client.dm(p_id, message) }
  end

  # === 2:2 전투 시작 ===
  def start_2v2(user1_id, user2_id, user3_id, user4_id, reply_id)
    users = [user1_id, user2_id, user3_id, user4_id].map { |id| @sheet_manager.find_user(id) }
    if users.any?(&:nil?)
      @mastodon_client.reply(reply_id, "참가자 중 등록되지 않은 사용자가 있습니다.", visibility: 'public')
      return
    end

    agility_rolls = users.map.with_index { |user, idx| [idx, (user["민첩"] || 10).to_i + rand(1..20)] }
    turn_order_indices = agility_rolls.sort_by { |_, agi| -agi }.map(&:first)
    all_ids = [user1_id, user2_id, user3_id, user4_id]
    turn_order = turn_order_indices.map { |i| all_ids[i] }

    BattleState.set({
      type: "2v2",
      participants: all_ids,
      teams: { team1: [user1_id, user2_id], team2: [user3_id, user4_id] },
      turn_order: turn_order,
      current_turn: turn_order[0],
      last_action_time: Time.now
    })

    names = users.map { |u| u["이름"] || u["ID"] }
    message = "2:2 전투 시작\n팀1: #{names[0]}, #{names[1]}\n팀2: #{names[2]}, #{names[3]}\n"
    message += "턴 순서: #{turn_order.map { |id| @sheet_manager.find_user(id)["이름"] || id }.join(' → ')}"

    @mastodon_client.post(message, visibility: 'public')
    all_ids.each { |p_id| @mastodon_client.dm(p_id, message) }
  end

  # === 허수아비 전투 ===
  def start_dummy_battle(user_id, difficulty, reply_id)
    user = @sheet_manager.find_user(user_id)
    unless user
      @mastodon_client.reply(reply_id, "등록되지 않은 사용자입니다.", visibility: 'public')
      return
    end

    dummy_id = "허수아비_#{difficulty}"
    user_agi = (user["민첩"] || 10).to_i + rand(1..20)
    dummy_agi = DUMMY_STATS[difficulty][:agi] + rand(1..20)
    turn_order = user_agi >= dummy_agi ? [user_id, dummy_id] : [dummy_id, user_id]

    BattleState.set({
      type: "dummy",
      difficulty: difficulty,
      participants: [user_id, dummy_id],
      turn_order: turn_order,
      current_turn: turn_order[0],
      dummy_hp: DUMMY_STATS[difficulty][:hp],
      last_action_time: Time.now
    })

    user_name = user["이름"] || user_id
    message = "허수아비(#{difficulty}) 전투 시작\n선공: #{turn_order[0] == user_id ? user_name : '허수아비'}"

    @mastodon_client.post(message, visibility: 'public')
    @mastodon_client.dm(user_id, message)

    dummy_turn if turn_order[0] == dummy_id
  end

  # === 공격 ===
  def attack(user_id)
    state = BattleState.get
    return unless state[:current_turn] == user_id
    attacker = @sheet_manager.find_user(user_id)
    atk = (attacker["공격력"] || 10).to_i
    atk_roll = rand(1..20)
    atk_total = atk + atk_roll
    attacker_name = attacker["이름"] || user_id

    if state[:type] == "dummy"
      difficulty = state[:difficulty]
      def_stat = DUMMY_STATS[difficulty][:def]
      def_roll = rand(1..20)
      def_total = def_stat + def_roll
      damage = [atk_total - def_total, 0].max
      state[:dummy_hp] -= damage

      message = "#{attacker_name}의 공격 (#{atk_roll}+#{atk}) vs 허수아비 방어 (#{def_roll}+#{def_stat})\n"
      message += "데미지: #{damage}, 허수아비 체력: #{state[:dummy_hp]}"
      @mastodon_client.post(message, visibility: 'public')
      @mastodon_client.dm(user_id, message)

      if state[:dummy_hp] <= 0
        end_message = "허수아비를 격파했습니다!"
        @mastodon_client.post(end_message, visibility: 'public')
        @mastodon_client.dm(user_id, end_message)
        BattleState.clear
      else
        BattleState.next_turn
        dummy_turn
      end
    else
      defender_id = find_opponent(user_id, state)
      defender = @sheet_manager.find_user(defender_id)
      def_stat = (defender["방어력"] || 10).to_i
      def_roll = rand(1..20)
      def_total = def_stat + def_roll
      damage = [atk_total - def_total, 0].max
      new_hp = [(defender["체력"] || 100).to_i - damage, 0].max
      @sheet_manager.update_stat(defender_id, "체력", new_hp)

      defender_name = defender["이름"] || defender_id
      message = "#{attacker_name}의 공격 (#{atk_roll}+#{atk}) vs #{defender_name}의 방어 (#{def_roll}+#{def_stat})\n"
      message += "데미지: #{damage}, #{defender_name} 체력: #{new_hp}"
      @mastodon_client.post(message, visibility: 'public')

      if new_hp <= 0
        end_message = "#{defender_name}이(가) 쓰러졌습니다! #{attacker_name} 승리!"
        @mastodon_client.post(end_message, visibility: 'public')
        BattleState.clear
      else
        BattleState.next_turn
      end
    end
  end

  private

  # === 허수아비 행동 ===
  def dummy_turn
    state = BattleState.get
    return unless state[:current_turn].include?("허수아비")
    difficulty = state[:difficulty]
    user_id = state[:participants].find { |p| !p.include?("허수아비") }
    user = @sheet_manager.find_user(user_id)
    user_name = user["이름"] || user_id

    atk = DUMMY_STATS[difficulty][:atk]
    atk_roll = rand(1..20)
    atk_total = atk + atk_roll
    def_stat = (user["방어력"] || 10).to_i
    def_roll = rand(1..20)
    def_total = def_stat + def_roll

    damage = [atk_total - def_total, 0].max
    new_hp = [(user["체력"] || 100).to_i - damage, 0].max
    @sheet_manager.update_stat(user_id, "체력", new_hp)

    message = "허수아비의 공격 (#{atk_roll}+#{atk}) vs #{user_name}의 방어 (#{def_roll}+#{def_stat})\n"
    message += "데미지: #{damage}, #{user_name} 체력: #{new_hp}"
    @mastodon_client.post(message, visibility: 'public')
    @mastodon_client.dm(user_id, message)

    if new_hp <= 0
      end_message = "#{user_name}이(가) 쓰러졌습니다! 허수아비 승리!"
      @mastodon_client.post(end_message, visibility: 'public')
      @mastodon_client.dm(user_id, end_message)
      BattleState.clear
    else
      BattleState.next_turn
    end
  end

  def find_opponent(user_id, state)
    if state[:type] == "1v1"
      state[:participants].find { |p| p != user_id }
    elsif state[:type] == "2v2"
      my_team = state[:teams][:team1].include?(user_id) ? :team1 : :team2
      enemy_team = my_team == :team1 ? :team2 : :team1
      alive = state[:teams][enemy_team].select do |pid|
        user = @sheet_manager.find_user(pid)
        user && (user["체력"] || 100).to_i > 0
      end
      alive.sample
    end
  end
end
