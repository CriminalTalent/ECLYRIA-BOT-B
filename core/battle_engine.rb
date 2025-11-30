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

  # ================================================================
  # 1v1 전투 시작
  # ================================================================
  def start_1v1(user1_id, user2_id, battle_id)
    # 이미 전투 중인지 확인
    if BattleState.battle_of(user1_id) || BattleState.battle_of(user2_id)
      @mastodon_client.reply(battle_id, "이미 전투 중인 참가자가 있습니다.")
      return
    end

    user1 = @sheet_manager.find_user(user1_id)
    user2 = @sheet_manager.find_user(user2_id)
    unless user1 && user2
      @mastodon_client.reply(battle_id, "참가자 중 등록되지 않은 사용자가 있습니다.")
      return
    end

    agi1 = (user1["민첩"] || 10).to_i + rand(1..20)
    agi2 = (user2["민첩"] || 10).to_i + rand(1..20)

    turn_order = agi1 >= agi2 ? [user1_id, user2_id] : [user2_id, user1_id]
    first_turn = turn_order[0]

    user1_name = user1["이름"] || user1_id
    user2_name = user2["이름"] || user2_id
    first_turn_name = (first_turn == user1_id ? user1_name : user2_name)

    message = "━━━━━━━━━━━━━━━━━━\n"
    message += "전투 시작: #{user1_name} vs #{user2_name}\n"
    message += "선공: #{first_turn_name}\n"
    message += "━━━━━━━━━━━━━━━━━━\n"
    message += "#{first_turn_name}의 차례\n"
    message += get_action_options(type: "1v1")

    @mastodon_client.reply_with_mentions(battle_id, message, [user1_id, user2_id])

    state = {
      type: "1v1",
      participants: [user1_id, user2_id],
      turn_order: turn_order,
      current_turn: first_turn,
      guarded: {},
      counter: {},
      reply_status: battle_id
    }

    BattleState.set(battle_id, state)
    BattleState.assign_user(user1_id, battle_id)
    BattleState.assign_user(user2_id, battle_id)
  end

  # ================================================================
  # 2v2 전투 시작
  # ================================================================
  def start_2v2(user1_id, user2_id, user3_id, user4_id, battle_id)
    ids = [user1_id, user2_id, user3_id, user4_id]
    if ids.any? { |id| BattleState.battle_of(id) }
      @mastodon_client.reply(battle_id, "이미 전투 중인 참가자가 있습니다.")
      return
    end

    users = ids.map { |id| @sheet_manager.find_user(id) }
    unless users.all?
      @mastodon_client.reply(battle_id, "참가자 중 등록되지 않은 사용자가 있습니다.")
      return
    end

    team1_agi = (users[0]["민첩"] || 10).to_i + (users[1]["민첩"] || 10).to_i + rand(1..20)
    team2_agi = (users[2]["민첩"] || 10).to_i + (users[3]["민첩"] || 10).to_i + rand(1..20)

    turn_order =
      if team1_agi >= team2_agi
        [user1_id, user2_id, user3_id, user4_id]
      else
        [user3_id, user4_id, user1_id, user2_id]
      end

    names = users.map { |u| u["이름"] }
    message = "━━━━━━━━━━━━━━━━━━\n"
    message += "2:2 전투 시작\n"
    message += "팀1: #{names[0]}, #{names[1]}\n"
    message += "팀2: #{names[2]}, #{names[3]}\n"
    message += "━━━━━━━━━━━━━━━━━━\n"

    first_turn = turn_order[0]
    first_turn_name = users[ids.index(first_turn)]["이름"]
    message += "#{first_turn_name}의 차례\n"
    message += get_action_options(type: "2v2")

    @mastodon_client.reply_with_mentions(battle_id, message, ids)

    state = {
      type: "2v2",
      participants: ids,
      teams: { team1: [user1_id, user2_id], team2: [user3_id, user4_id] },
      turn_order: turn_order,
      current_turn: first_turn,
      round: 1,
      turn_index: 0,
      guarded: {},
      counter: {},
      actions_queue: [],
      reply_status: battle_id
    }

    BattleState.set(battle_id, state)
    ids.each { |id| BattleState.assign_user(id, battle_id) }
  end

  # ================================================================
  # 공격(1v1 / 2v2)
  # ================================================================
  def attack(user_id, battle_id, target_id = nil)
    state = BattleState.get(battle_id)
    return unless state && state[:current_turn].to_s == user_id.to_s

    attacker = @sheet_manager.find_user(user_id)
    return unless attacker

    case state[:type]
    when "2v2"
      return reply("타겟 필요", state) unless target_id
      return reply("잘못된 타겟", state) unless state[:participants].include?(target_id)
      return reply("아군 공격 불가", state) if same_team?(user_id, target_id, state)

      state[:actions_queue] << { user_id: user_id, action: :attack, target: target_id }
      next_turn_2v2(state, battle_id, "#{attacker["이름"]}의 공격 준비")
    when "1v1"
      target_id ||= find_opponent(user_id, state)
      resolve_attack(user_id, target_id, battle_id, state)
    when "dummy"
      resolve_dummy_attack(user_id, battle_id, state)
    end
  end

  # ================================================================
  # 방어(1v1 / 2v2)
  # ================================================================
  def defend(user_id, battle_id, target_id = nil)
    state = BattleState.get(battle_id)
    return unless state && state[:current_turn].to_s == user_id.to_s

    case state[:type]
    when "2v2"
      if target_id
        return reply("대상 없음", state) unless state[:participants].include?(target_id)
        state[:actions_queue] << { user_id: user_id, action: :defend_target, target: target_id }
        next_turn_2v2(state, battle_id, "방어 준비")
      else
        state[:actions_queue] << { user_id: user_id, action: :defend }
        next_turn_2v2(state, battle_id, "방어 태세")
      end
    else
      state[:guarded][user_id] = true
      next_turn_basic(user_id, battle_id, state, "방어 태세")
    end
  end

  # ================================================================
  # 반격(1v1 / 2v2)
  # ================================================================
  def counter(user_id, battle_id)
    state = BattleState.get(battle_id)
    return unless state && state[:current_turn].to_s == user_id.to_s

    if state[:type] == "2v2"
      state[:actions_queue] << { user_id: user_id, action: :counter }
      next_turn_2v2(state, battle_id, "반격 준비")
    else
      state[:counter][user_id] = true
      next_turn_basic(user_id, battle_id, state, "반격 태세")
    end
  end

  # ================================================================
  # 도주
  # ================================================================
  def flee(user_id, battle_id)
    state = BattleState.get(battle_id)
    return reply("전투 상태 없음", state) unless state
    return reply("참가자 아님", state) unless state[:participants].include?(user_id)

    user = @sheet_manager.find_user(user_id)
    name = user["이름"] || user_id

    if rand(1..20) + (user["행운"] || 10).to_i >= 20
      reply("#{name} 도주 성공! 전투 종료", state)
      BattleState.clear(battle_id)
    else
      next_turn_basic(user_id, battle_id, state, "#{name} 도주 실패")
    end
  end

  # ================================================================
  # 내부 처리 메서드
  # ================================================================
  private

  def reply(msg, state)
    @mastodon_client.reply(state[:reply_status], msg)
  end

  def reply_with_mentions(msg, state)
    @mastodon_client.reply_with_mentions(state[:reply_status], msg, state[:participants])
  end

  def same_team?(id1, id2, state)
    state[:teams].values.any? { |team| team.include?(id1) && team.include?(id2) }
  end

  def next_turn_basic(user_id, battle_id, state, prefix)
    rotate_turn(battle_id, state)
    next_player = state[:current_turn]
    name = @sheet_manager.find_user(next_player)["이름"]
    msg = "#{prefix}\n━━━━━━━━━━━━━━━━━━\n#{name}의 차례\n#{get_action_options(state: state)}"
    reply_with_mentions(msg, state)
  end

  def next_turn_2v2(state, battle_id, prefix)
    state[:turn_index] += 1

    if state[:turn_index] >= state[:turn_order].length
      resolve_2v2_round(battle_id, state, prefix)
      return
    end

    state[:current_turn] = state[:turn_order][state[:turn_index]]
    name = @sheet_manager.find_user(state[:current_turn])["이름"]
    msg = "#{prefix}\n━━━━━━━━━━━━━━━━━━\n#{name}의 차례\n#{get_action_options(state: state)}"
    reply_with_mentions(msg, state)
  end

  def resolve_attack(attacker_id, defender_id, battle_id, state)
    attacker = @sheet_manager.find_user(attacker_id)
    defender = @sheet_manager.find_user(defender_id)

    atk_roll = rand(1..20)
    atk_total = atk_roll + (attacker["공격"] || 10).to_i

    def_roll = rand(1..20)
    def_total = def_roll + (defender["방어"] || 10).to_i

    damage = [atk_total - def_total, 0].max

    new_hp = [(defender["HP"] || 100).to_i - damage, 0].max
    @sheet_manager.update_user(defender_id, { hp: new_hp })

    msg = "#{attacker["이름"]} 공격\n데미지: #{damage}\n#{defender["이름"]} HP: #{new_hp}\n━━━━━━━━━━━━━━━━━━"

    if new_hp <= 0
      msg += "\n#{attacker["이름"]} 승리!"
      reply_with_mentions(msg, state)
      BattleState.clear(battle_id)
      return
    end

    rotate_turn(battle_id, state)
    next_name = @sheet_manager.find_user(state[:current_turn])["이름"]
    msg += "\n#{next_name}의 차례\n#{get_action_options(state: state)}"
    reply_with_mentions(msg, state)
  end

  def resolve_dummy_attack(user_id, battle_id, state)
    user = @sheet_manager.find_user(user_id)
    difficulty = state[:difficulty]
    attacker_name = user["이름"]

    atk_roll = rand(1..20)
    atk_total = atk_roll + (user["공격"] || 10).to_i

    def_roll = rand(1..20)
    def_total = def_roll + DUMMY_STATS[difficulty][:def]

    damage = [atk_total - def_total, 0].max
    state[:dummy_hp] -= damage

    msg = "#{attacker_name} 공격\n데미지: #{damage}\n허수아비 HP: #{state[:dummy_hp]}\n━━━━━━━━━━━━━━━━━━"

    if state[:dummy_hp] <= 0
      msg += "\n격파 성공!"
      reply_with_mentions(msg, state)
      BattleState.clear(battle_id)
      return
    end

    rotate_turn(battle_id, state)
    msg += "\n#{attacker_name}의 차례\n#{get_action_options(state: state)}"
    reply_with_mentions(msg, state)
  end

  def resolve_2v2_round(battle_id, state, prefix)
    state[:actions_queue].each do |act|
      next unless act[:action] == :attack
      resolve_attack(act[:user_id], act[:target], battle_id, state)
    end

    state[:round] += 1
    state[:turn_index] = 0
    state[:current_turn] = state[:turn_order][0]
    state[:actions_queue] = []

    name = @sheet_manager.find_user(state[:current_turn])["이름"]
    msg = "#{prefix}\n\n라운드 #{state[:round]} 시작\n#{name}의 차례\n#{get_action_options(state: state)}"

    reply_with_mentions(msg, state)
  end

  def rotate_turn(battle_id, state)
    idx = state[:turn_order].index(state[:current_turn])
    state[:current_turn] = state[:turn_order][(idx + 1) % state[:turn_order].length]
  end

  def get_action_options(options = {})
    state = options[:state]
    if state && state[:type] == "2v2"
      "[공격/@타겟] [방어/@타겟] [반격] [물약사용] [도주]"
    else
      "[공격] [방어] [반격] [물약사용] [도주]"
    end
  end
end
