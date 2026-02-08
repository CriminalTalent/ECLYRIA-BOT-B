require_relative 'battle_state'

class BattleEngine
  # 팀명 상수
  TEAM_NAMES = {
    team1: "불사조 기사단",
    team2: "이그드라실"
  }

  def initialize(mastodon_client, sheet_manager)
    @mastodon_client = mastodon_client
    @sheet_manager   = sheet_manager
  end

  # 1:1 전투 시작
  def start_1v1(user1_id, user2_id, reply_status)
    # 자기 자신과의 전투 방지
    if user1_id == user2_id
      @mastodon_client.reply(reply_status, "자기 자신과는 전투할 수 없습니다.")
      return
    end

    # 이미 전투 중인지 확인
    if BattleState.find_by_user(user1_id)
      user1_name = (@sheet_manager.find_user(user1_id) || {})["이름"] || user1_id
      @mastodon_client.reply(reply_status, "#{user1_name}님은 이미 전투 중입니다.")
      return
    end

    if BattleState.find_by_user(user2_id)
      user2_name = (@sheet_manager.find_user(user2_id) || {})["이름"] || user2_id
      @mastodon_client.reply(reply_status, "#{user2_name}님은 이미 전투 중입니다.")
      return
    end

    user1 = @sheet_manager.find_user(user1_id)
    user2 = @sheet_manager.find_user(user2_id)
    unless user1 && user2
      @mastodon_client.reply(reply_status, "참가자 중 등록되지 않은 사용자가 있습니다.")
      return
    end

    # 민첩성 판정
    agi1 = (user1["민첩성"] || 10).to_i + rand(1..20)
    agi2 = (user2["민첩성"] || 10).to_i + rand(1..20)
    turn_order = agi1 >= agi2 ? [user1_id, user2_id] : [user2_id, user1_id]

    user1_name = user1["이름"] || user1_id
    user2_name = user2["이름"] || user2_id
    first_turn_name = turn_order[0] == user1_id ? user1_name : user2_name
    first_agi = agi1 >= agi2 ? agi1 : agi2

    # DM 여부 확인
    visibility = get_visibility(reply_status)

    message = "━━━━━━━━━━━━━━━━━━\n"
    message += "전투 시작: #{user1_name} vs #{user2_name}\n"
    message += "선공: #{first_turn_name} (민첩 #{first_agi})\n"
    message += "━━━━━━━━━━━━━━━━━━\n"
    message += "제한시간: 1인당 4분, 전체 1시간\n"
    message += "━━━━━━━━━━━━━━━━━━\n"
    message += "#{first_turn_name}의 차례\n"
    message += "[공격] [방어] [반격] [물약사용/크기]"

    result = reply_with_mentions_to_battle(reply_status, message, [user1_id, user2_id], visibility)

    battle_id = BattleState.create([user1_id, user2_id], {
      type: "1v1",
      participants: [user1_id, user2_id],
      turn_order: turn_order,
      current_turn: nil,  # 동시 행동이므로 nil
      round: 1,
      actions_queue: [],
      guarded: {},
      counter: {},
      guarded_used: {},   # 방어 사용 여부 추적
      counter_used: {},   # 반격 사용 여부 추적
      reply_status: result || reply_status,
      visibility: visibility
    })

    puts "[전투] 1:1 전투 생성: #{battle_id}"
  end

  # 2:2 전투 시작
  def start_2v2(user1_id, user2_id, user3_id, user4_id, reply_status)
    ids = [user1_id, user2_id, user3_id, user4_id]

    # 이미 전투 중인지 확인
    ids.each do |id|
      if BattleState.find_by_user(id)
        user_name = (@sheet_manager.find_user(id) || {})["이름"] || id
        @mastodon_client.reply(reply_status, "#{user_name}님은 이미 전투 중입니다.")
        return
      end
    end

    users = ids.map { |id| @sheet_manager.find_user(id) }
    if users.any?(&:nil?)
      @mastodon_client.reply(reply_status, "참가자 중 등록되지 않은 사용자가 있습니다.")
      return
    end

    # 팀 구성: A,B vs C,D
    team1 = [user1_id, user2_id]
    team2 = [user3_id, user4_id]

    # 민첩성 판정 (팀별 합산)
    team1_agi = team1.sum { |id| (users[ids.index(id)]["민첩성"] || 10).to_i } + rand(1..20)
    team2_agi = team2.sum { |id| (users[ids.index(id)]["민첩성"] || 10).to_i } + rand(1..20)

    # 선공 팀 결정
    first_team_key = team1_agi >= team2_agi ? :team1 : :team2
    first_team = team1_agi >= team2_agi ? team1 : team2
    second_team = team1_agi >= team2_agi ? team2 : team1

    # 각 팀 내에서 민첩성 순으로 정렬
    first_team_sorted = first_team.sort_by { |id| -(users[ids.index(id)]["민첩성"] || 10).to_i }
    second_team_sorted = second_team.sort_by { |id| -(users[ids.index(id)]["민첩성"] || 10).to_i }
    turn_order = first_team_sorted + second_team_sorted

    names = ids.map { |id| (users[ids.index(id)]["이름"] || id) }

    # 첫 번째 차례 (선공팀 중 민첩성 1위)
    first_player_id = turn_order[0]
    first_player_name = users[ids.index(first_player_id)]["이름"] || first_player_id

    # DM 여부 확인
    visibility = get_visibility(reply_status)

    message = "━━━━━━━━━━━━━━━━━━\n"
    message += "팀전투 시작: #{names[0]}, #{names[1]} vs #{names[2]}, #{names[3]}\n"
    message += "선공: #{TEAM_NAMES[first_team_key]} (민첩 #{[team1_agi, team2_agi].max})\n"
    message += "━━━━━━━━━━━━━━━━━━\n"
    message += "제한시간: 1인당 4분, 전체 1시간\n"
    message += "━━━━━━━━━━━━━━━━━━\n"
    message += "#{first_player_name}의 차례\n"
    message += "[공격/@타겟] [방어/@타겟] [반격] [물약사용/크기/@타겟]"

    result = reply_with_mentions_to_battle(reply_status, message, ids, visibility)

    battle_id = BattleState.create(ids, {
      type: "2v2",
      participants: ids,
      teams: { team1: team1, team2: team2 },
      turn_order: turn_order,
      current_turn: nil,  # 동시 행동
      round: 1,
      actions_queue: [],
      guarded: {},
      counter: {},
      guarded_used: {},
      counter_used: {},
      reply_status: result || reply_status,
      visibility: visibility
    })

    puts "[전투] 2:2 전투 생성: #{battle_id}"
  end

  # 4:4 전투 시작
  def start_4v4(u1, u2, u3, u4, u5, u6, u7, u8, reply_status)
    ids = [u1, u2, u3, u4, u5, u6, u7, u8]

    ids.each do |id|
      if BattleState.find_by_user(id)
        user_name = (@sheet_manager.find_user(id) || {})["이름"] || id
        @mastodon_client.reply(reply_status, "#{user_name}님은 이미 전투 중입니다.")
        return
      end
    end

    users = ids.map { |id| @sheet_manager.find_user(id) }
    if users.any?(&:nil?)
      @mastodon_client.reply(reply_status, "참가자 중 등록되지 않은 사용자가 있습니다.")
      return
    end

    # 팀 구성
    team1 = [u1, u2, u3, u4]
    team2 = [u5, u6, u7, u8]

    # 민첩성 판정
    team1_agi = team1.sum { |id| (@sheet_manager.find_user(id)["민첩성"] || 10).to_i } + rand(1..20)
    team2_agi = team2.sum { |id| (@sheet_manager.find_user(id)["민첩성"] || 10).to_i } + rand(1..20)

    first_team_key = team1_agi >= team2_agi ? :team1 : :team2
    first_team = team1_agi >= team2_agi ? team1 : team2
    second_team = team1_agi >= team2_agi ? team2 : team1

    # 각 팀 내에서 민첩성 순으로 정렬
    first_team_sorted = first_team.sort_by { |id| -(@sheet_manager.find_user(id)["민첩성"] || 10).to_i }
    second_team_sorted = second_team.sort_by { |id| -(@sheet_manager.find_user(id)["민첩성"] || 10).to_i }
    turn_order = first_team_sorted + second_team_sorted

    names = ids.map { |id| (@sheet_manager.find_user(id)["이름"] || id) }

    # 첫 번째 차례 (선공팀 중 민첩성 1위)
    first_player_id = turn_order[0]
    first_player_name = @sheet_manager.find_user(first_player_id)["이름"] || first_player_id

    # DM 여부 확인
    visibility = get_visibility(reply_status)

    message = "━━━━━━━━━━━━━━━━━━\n"
    message += "대규모전투 시작!\n"
    message += "#{TEAM_NAMES[:team1]}: #{names[0..3].join(', ')}\n"
    message += "#{TEAM_NAMES[:team2]}: #{names[4..7].join(', ')}\n"
    message += "선공: #{TEAM_NAMES[first_team_key]} (민첩 #{[team1_agi, team2_agi].max})\n"
    message += "━━━━━━━━━━━━━━━━━━\n"
    message += "제한시간: 1인당 4분, 전체 1시간\n"
    message += "━━━━━━━━━━━━━━━━━━\n"
    message += "#{first_player_name}의 차례\n"
    message += "[공격/@타겟] [방어/@타겟] [반격] [물약사용/크기/@타겟]"

    result = reply_with_mentions_to_battle(reply_status, message, ids, visibility)

    battle_id = BattleState.create(ids, {
      type: "4v4",
      participants: ids,
      teams: { team1: team1, team2: team2 },
      turn_order: turn_order,
      current_turn: nil,
      round: 1,
      actions_queue: [],
      guarded: {},
      counter: {},
      guarded_used: {},
      counter_used: {},
      reply_status: result || reply_status,
      visibility: visibility
    })

    puts "[전투] 4:4 전투 생성: #{battle_id}"
  end

  # 공격
  def attack(user_id, target_id = nil)
    battle_id = BattleState.find_battle_id_by_user(user_id)
    state = BattleState.get(battle_id)

    unless state
      return
    end

    if already_acted?(user_id, state)
      reply_to_battle_thread("이미 이번 라운드에 행동을 선택했습니다.", battle_id, state)
      return
    end

    if state[:type] == "1v1"
      # 1:1에서는 자동으로 상대방이 타겟
      target_id ||= find_opponent(user_id, state)
      queue_action(user_id, :attack, target_id, battle_id, state)
    else
      # 팀전투에서는 타겟 필수
      unless target_id
        reply_to_battle_thread("팀전투에서는 [공격/@타겟] 형식으로 타겟을 지정해야 합니다.", battle_id, state)
        return
      end

      unless state[:participants].include?(target_id)
        reply_to_battle_thread("잘못된 타겟입니다.", battle_id, state)
        return
      end

      my_team = state[:teams][:team1].include?(user_id) ? :team1 : :team2
      if state[:teams][my_team].include?(target_id)
        reply_to_battle_thread("아군을 공격할 수 없습니다!", battle_id, state)
        return
      end

      queue_action(user_id, :attack, target_id, battle_id, state)
    end
  end

  # 방어
  def defend(user_id)
    battle_id = BattleState.find_battle_id_by_user(user_id)
    state = BattleState.get(battle_id)

    unless state
      return
    end

    if already_acted?(user_id, state)
      reply_to_battle_thread("이미 이번 라운드에 행동을 선택했습니다.", battle_id, state)
      return
    end

    queue_action(user_id, :defend, nil, battle_id, state)
  end

  # 아군 방어
  def defend_target(user_id, target_id)
    battle_id = BattleState.find_battle_id_by_user(user_id)
    state = BattleState.get(battle_id)

    unless state
      return
    end

    if already_acted?(user_id, state)
      reply_to_battle_thread("이미 이번 라운드에 행동을 선택했습니다.", battle_id, state)
      return
    end

    unless state[:participants].include?(target_id)
      reply_to_battle_thread("전투 참가자가 아닙니다.", battle_id, state)
      return
    end

    if state[:type] == "1v1"
      reply_to_battle_thread("1:1 전투에서는 [방어]만 사용할 수 있습니다.", battle_id, state)
      return
    end

    queue_action(user_id, :defend_target, target_id, battle_id, state)
  end

  # 반격
  def counter(user_id)
    battle_id = BattleState.find_battle_id_by_user(user_id)
    state = BattleState.get(battle_id)

    unless state
      return
    end

    if already_acted?(user_id, state)
      reply_to_battle_thread("이미 이번 라운드에 행동을 선택했습니다.", battle_id, state)
      return
    end

    queue_action(user_id, :counter, nil, battle_id, state)
  end

  # 물약 사용 (전투 중)
  def use_potion(user_id, potion_type, target_id = nil)
    battle_id = BattleState.find_battle_id_by_user(user_id)
    state = BattleState.get(battle_id)

    unless state
      return
    end

    if already_acted?(user_id, state)
      reply_to_battle_thread("이미 이번 라운드에 행동을 선택했습니다.", battle_id, state)
      return
    end

    queue_action(user_id, :use_potion, target_id || user_id, battle_id, state, { potion_type: potion_type })
  end

  # 시간 초과 시 자동 방어
  def auto_defend_timeout(battle_id, state)
    alive_participants = get_alive_participants(state)
    acted_users = (state[:actions_queue] || []).map { |a| a[:user_id] }

    not_acted = alive_participants.reject { |pid| acted_users.include?(pid) }

    not_acted.each do |user_id|
      state[:actions_queue] ||= []
      state[:actions_queue] << {
        user_id: user_id,
        action: :defend,
        target: nil
      }
    end

    state[:last_action_time] = Time.now
    BattleState.update(battle_id, state)

    not_acted_names = not_acted.map { |pid| (@sheet_manager.find_user(pid) || {})["이름"] || pid }

    message = "시간 초과!\n"
    message += "#{not_acted_names.join(', ')}이(가) 4분 내에 행동하지 않아 자동으로 방어합니다.\n"
    message += "━━━━━━━━━━━━━━━━━━\n"

    reply_to_battle_thread(message, battle_id, state)

    process_round(battle_id, state)
  end

  # 전투 시간 초과 시 체력 총합으로 승부
  def end_battle_by_hp_total(battle_id, state)
    message = "전투 시간 1시간 초과!\n"
    message += "━━━━━━━━━━━━━━━━━━\n"

    if state[:type] == "1v1"
      user1_id = state[:participants][0]
      user2_id = state[:participants][1]

      user1 = @sheet_manager.find_user(user1_id)
      user2 = @sheet_manager.find_user(user2_id)

      hp1 = (user1["HP"] || 0).to_i
      hp2 = (user2["HP"] || 0).to_i

      user1_name = user1["이름"] || user1_id
      user2_name = user2["이름"] || user2_id

      message += "체력 비교:\n"
      message += "#{user1_name}: #{hp1}HP\n"
      message += "#{user2_name}: #{hp2}HP\n"
      message += "━━━━━━━━━━━━━━━━━━\n"

      if hp1 > hp2
        message += "#{user1_name} 승리! (체력 총합)"
      elsif hp2 > hp1
        message += "#{user2_name} 승리! (체력 총합)"
      else
        message += "무승부!"
      end
    else
      # 팀전투
      team1_hp = state[:teams][:team1].sum do |pid|
        user = @sheet_manager.find_user(pid)
        (user["HP"] || 0).to_i
      end

      team2_hp = state[:teams][:team2].sum do |pid|
        user = @sheet_manager.find_user(pid)
        (user["HP"] || 0).to_i
      end

      message += "팀별 체력 총합:\n"
      message += "#{TEAM_NAMES[:team1]}: #{team1_hp}HP\n"
      message += "#{TEAM_NAMES[:team2]}: #{team2_hp}HP\n"
      message += "━━━━━━━━━━━━━━━━━━\n"

      if team1_hp > team2_hp
        message += "#{TEAM_NAMES[:team1]} 승리! (체력 총합)"
      elsif team2_hp > team1_hp
        message += "#{TEAM_NAMES[:team2]} 승리! (체력 총합)"
      else
        message += "무승부!"
      end
    end

    reply_to_battle_thread(message, battle_id, state)
    BattleState.clear(battle_id)
  end

  private

  def get_visibility(status)
    vis = status["visibility"] || status[:visibility]
    vis == "direct" ? "direct" : "unlisted"
  end

  def reply_with_mentions_to_battle(reply_status, message, user_ids, visibility = "unlisted")
    @mastodon_client.reply_with_mentions_visibility(reply_status, message, user_ids, visibility)
  rescue => e
    puts "[BattleEngine] reply_with_mentions_to_battle 실패: #{e.message}"
    @mastodon_client.reply_with_mentions(reply_status, message, user_ids)
  end

  # 체력바 생성
  def create_hp_bar(current_hp, max_hp)
    percentage = [current_hp.to_f / max_hp, 1.0].min
    filled_length = (percentage * 10).round

    filled = "█" * filled_length
    empty = "░" * (10 - filled_length)

    filled + empty
  end

  # 최대 HP 계산
  def calculate_max_hp(user)
    vitality_stat = (user["체력"] || 0).to_i
    100 + (vitality_stat * 10)
  end

  # 상대방 찾기 (1:1)
  def find_opponent(user_id, state)
    state[:participants].find { |p| p != user_id }
  end

  def check_critical_hit(luck)
    crit_chance = case luck.to_i
                  when 1 then 5
                  when 2 then 10
                  when 3 then 10
                  when 4 then 15
                  when 5 then 15
                  when 6 then 20
                  when 7 then 20
                  when 8 then 25
                  when 9 then 25
                  when 10 then 30
                  else [luck.to_i * 3, 50].min
                  end
    is_crit = rand(1..100) <= crit_chance
    { is_crit: is_crit, chance: crit_chance }
  end

  def reply_to_battle_thread(message, battle_id, state)
    return unless state[:reply_status]
    visibility = state[:visibility] || "unlisted"
    participants = state[:participants] || []

    result = @mastodon_client.reply_with_mentions_visibility(
      state[:reply_status], message, participants, visibility
    )
    if result
      state[:reply_status] = result
      BattleState.update(battle_id, state)
    end
    result
  rescue => e
    puts "[BattleEngine] reply_to_battle_thread 실패: #{e.message}"
    @mastodon_client.reply(state[:reply_status], message)
  end

  def already_acted?(user_id, state)
    (state[:actions_queue] || []).any? { |a| a[:user_id] == user_id }
  end

  def queue_action(user_id, action_type, target_id, battle_id, state, extra = {})
    state[:actions_queue] ||= []

    action = {
      user_id: user_id,
      action: action_type,
      target: target_id
    }.merge(extra)

    state[:actions_queue] << action
    state[:last_action_time] = Time.now
    BattleState.update(battle_id, state)

    user = @sheet_manager.find_user(user_id)
    user_name = user ? (user["이름"] || user_id) : user_id

    action_text = case action_type
                  when :attack
                    target_name = (@sheet_manager.find_user(target_id) || {})["이름"] || target_id
                    "#{user_name}이(가) #{target_name}을(를) 공격 준비"
                  when :defend
                    "#{user_name}이(가) 방어 태세"
                  when :defend_target
                    target_name = (@sheet_manager.find_user(target_id) || {})["이름"] || target_id
                    "#{user_name}이(가) #{target_name}을(를) 방어 준비"
                  when :counter
                    "#{user_name}이(가) 반격 태세"
                  when :use_potion
                    potion_type = extra[:potion_type]
                    if target_id == user_id
                      "#{user_name}이(가) #{potion_type}물약 사용 준비"
                    else
                      target_name = (@sheet_manager.find_user(target_id) || {})["이름"] || target_id
                      "#{user_name}이(가) #{target_name}에게 #{potion_type}물약 사용 준비"
                    end
                  end

    alive_participants = get_alive_participants(state)
    actions_count = state[:actions_queue].length

    message = "#{action_text}\n"
    message += "━━━━━━━━━━━━━━━━━━\n"

    if actions_count >= alive_participants.length
      process_round(battle_id, state)
    else
      acted_users = state[:actions_queue].map { |a| a[:user_id] }
      # turn_order 순서대로 아직 행동하지 않은 생존자 찾기
      waiting_ordered = state[:turn_order].select do |pid|
        alive_participants.include?(pid) && !acted_users.include?(pid)
      end

      if state[:type] == "1v1"
        # 1:1: "{이름}의 차례" 형식
        next_player_name = (@sheet_manager.find_user(waiting_ordered.first) || {})["이름"] || waiting_ordered.first
        message += "#{next_player_name}의 차례\n"
        message += "[공격] [방어] [반격] [물약사용/크기]"
      else
        # 팀전투: 다음 차례인 한 명만 표시
        next_player_id = waiting_ordered.first
        next_player_name = (@sheet_manager.find_user(next_player_id) || {})["이름"] || next_player_id
        message += "#{next_player_name}의 차례\n"
        message += "[공격/@타겟] [방어/@타겟] [반격] [물약사용/크기/@타겟]"
      end

      reply_to_battle_thread(message, battle_id, state)
    end
  end

  def get_alive_participants(state)
    state[:participants].select do |pid|
      user = @sheet_manager.find_user(pid)
      user && (user["HP"] || 0).to_i > 0
    end
  end

  # 라운드 처리: 물약 > 방어/반격 > 공격 순서
  def process_round(battle_id, state)
    message1 = "라운드 #{state[:round]} 결과\n"
    message1 += "━━━━━━━━━━━━━━━━━━\n\n"

    # 1단계: 물약
    state[:actions_queue].each do |action|
      next unless action[:action] == :use_potion

      user_id = action[:user_id]
      target_id = action[:target]
      potion_type = action[:potion_type]

      result = process_potion_action(user_id, target_id, potion_type)
      message1 += result[:message] + "\n" if result[:message]
    end

    # 방어/반격 상태 설정
    state[:guarded] = {}
    state[:counter] = {}
    state[:guarded_used] = {}
    state[:counter_used] = {}
    state[:defend_target_map] = {}

    state[:actions_queue].each do |action|
      case action[:action]
      when :defend
        state[:guarded][action[:user_id]] = true
      when :defend_target
        # 대리 방어: 아군에 대한 공격을 자신이 받음
        state[:guarded][action[:user_id]] = true
        state[:defend_target_map][action[:target]] = action[:user_id]
      when :counter
        # 반격: 방어 보너스 없이 반격 데미지만 적용
        state[:counter][action[:user_id]] = true
      end
    end

    # 공격 처리 (민첩성순)
    attack_actions = state[:actions_queue].select { |a| a[:action] == :attack }

    # 민첩성 순으로 정렬
    attack_actions.sort_by! do |action|
      user = @sheet_manager.find_user(action[:user_id])
      -(user ? (user["민첩성"] || 0).to_i : 0)
    end

    attack_actions.each do |action|
      attacker_id = action[:user_id]
      original_defender_id = action[:target]

      # 대리 방어 확인
      actual_defender_id = state[:defend_target_map][original_defender_id] || original_defender_id

      attacker = @sheet_manager.find_user(attacker_id)
      defender = @sheet_manager.find_user(actual_defender_id)

      next unless attacker && defender

      if (attacker["HP"] || 0).to_i <= 0
        next
      end

      if (defender["HP"] || 0).to_i <= 0
        next
      end

      result = calculate_attack_result(attacker, attacker_id, defender, actual_defender_id, state, original_defender_id != actual_defender_id)
      message1 += result[:message] + "\n"

      # HP 업데이트
      if result[:damage] > 0
        new_hp = [(defender["HP"] || 100).to_i - result[:damage], 0].max
        @sheet_manager.update_user(actual_defender_id, { "HP" => new_hp })
      end

      if result[:counter_damage] > 0
        attacker_new_hp = [(attacker["HP"] || 100).to_i - result[:counter_damage], 0].max
        @sheet_manager.update_user(attacker_id, { "HP" => attacker_new_hp })
      end
    end

    # 1번 타래 전송
    result1 = reply_to_battle_thread(message1, battle_id, state)

    # 0.5초 대기
    sleep 0.5

    # 2번 타래: 체력 현황
    message2 = "━━━━━━━━━━━━━━━━━━\n"
    message2 += "체력 현황\n"
    message2 += "━━━━━━━━━━━━━━━━━━\n"

    if state[:type] == "1v1"
      # 1:1 체력 표시
      state[:participants].each do |pid|
        user = @sheet_manager.find_user(pid)
        next unless user

        user_name = user["이름"] || pid
        current_hp = (user["HP"] || 0).to_i
        max_hp = calculate_max_hp(user)
        hp_bar = create_hp_bar(current_hp, max_hp)

        message2 += "#{user_name}: #{hp_bar} #{current_hp}/#{max_hp}\n"
      end
    else
      # 팀전투 체력 표시
      message2 += "#{TEAM_NAMES[:team1]}:\n"
      state[:teams][:team1].each do |pid|
        user = @sheet_manager.find_user(pid)
        next unless user

        user_name = user["이름"] || pid
        current_hp = (user["HP"] || 0).to_i
        max_hp = calculate_max_hp(user)
        hp_bar = create_hp_bar(current_hp, max_hp)
        status = current_hp > 0 ? "(생존)" : "(전투불능)"

        message2 += "- #{user_name}: #{hp_bar} #{current_hp}/#{max_hp} #{status}\n"
      end

      message2 += "\n#{TEAM_NAMES[:team2]}:\n"
      state[:teams][:team2].each do |pid|
        user = @sheet_manager.find_user(pid)
        next unless user

        user_name = user["이름"] || pid
        current_hp = (user["HP"] || 0).to_i
        max_hp = calculate_max_hp(user)
        hp_bar = create_hp_bar(current_hp, max_hp)
        status = current_hp > 0 ? "(생존)" : "(전투불능)"

        message2 += "- #{user_name}: #{hp_bar} #{current_hp}/#{max_hp} #{status}\n"
      end
    end
    message2 += "━━━━━━━━━━━━━━━━━━\n\n"

    # 승부 판정
    if state[:type] == "1v1"
      user1_hp = (@sheet_manager.find_user(state[:participants][0])["HP"] || 0).to_i
      user2_hp = (@sheet_manager.find_user(state[:participants][1])["HP"] || 0).to_i

      user1_name = (@sheet_manager.find_user(state[:participants][0]) || {})["이름"] || state[:participants][0]
      user2_name = (@sheet_manager.find_user(state[:participants][1]) || {})["이름"] || state[:participants][1]

      if user1_hp <= 0 && user2_hp <= 0
        message2 += "무승부! (동시 전투불능)"
        reply_to_battle_thread(message2, battle_id, state)
        BattleState.clear(battle_id)
        return
      elsif user1_hp <= 0
        message2 += "#{user2_name} 승리!"
        reply_to_battle_thread(message2, battle_id, state)
        BattleState.clear(battle_id)
        return
      elsif user2_hp <= 0
        message2 += "#{user1_name} 승리!"
        reply_to_battle_thread(message2, battle_id, state)
        BattleState.clear(battle_id)
        return
      end
    else
      # 팀전투 승부 판정
      team1_alive = state[:teams][:team1].count do |pid|
        u = @sheet_manager.find_user(pid)
        u && (u["HP"] || 0).to_i > 0
      end

      team2_alive = state[:teams][:team2].count do |pid|
        u = @sheet_manager.find_user(pid)
        u && (u["HP"] || 0).to_i > 0
      end

      if team1_alive == 0 && team2_alive == 0
        message2 += "무승부! (동시 전멸)"
        reply_to_battle_thread(message2, battle_id, state)
        BattleState.clear(battle_id)
        return
      elsif team1_alive == 0
        message2 += "#{TEAM_NAMES[:team2]} 승리!"
        reply_to_battle_thread(message2, battle_id, state)
        BattleState.clear(battle_id)
        return
      elsif team2_alive == 0
        message2 += "#{TEAM_NAMES[:team1]} 승리!"
        reply_to_battle_thread(message2, battle_id, state)
        BattleState.clear(battle_id)
        return
      end
    end

    # 다음 라운드
    state[:round] += 1
    state[:actions_queue] = []
    state[:guarded] = {}
    state[:counter] = {}
    state[:guarded_used] = {}
    state[:counter_used] = {}
    state[:defend_target_map] = {}
    state[:last_action_time] = Time.now
    BattleState.update(battle_id, state)

    # 다음 라운드 첫 번째 차례: turn_order에서 생존자 중 첫 번째
    alive_next = get_alive_participants(state)
    first_alive_in_order = state[:turn_order].find { |pid| alive_next.include?(pid) }
    first_player = @sheet_manager.find_user(first_alive_in_order)
    first_player_name = first_player ? (first_player["이름"] || first_alive_in_order) : first_alive_in_order

    if state[:type] == "1v1"
      message2 += "다음 라운드 시작\n"
      message2 += "#{first_player_name}의 차례\n"
      message2 += "[공격] [방어] [반격] [물약사용/크기]"
    else
      message2 += "라운드 #{state[:round]} 시작\n"
      message2 += "#{first_player_name}의 차례\n"
      message2 += "[공격/@타겟] [방어/@타겟] [반격] [물약사용/크기/@타겟]"
    end

    reply_to_battle_thread(message2, battle_id, state)
  end

  # 물약 액션 처리
  def process_potion_action(user_id, target_id, potion_type)
    potion_effects = { "소형" => 10, "중형" => 30, "대형" => 50 }
    heal_amount = potion_effects[potion_type] || 0

    user = @sheet_manager.find_user(user_id)
    target = @sheet_manager.find_user(target_id)

    return { message: "" } unless user && target

    user_name = user["이름"] || user_id
    target_name = target["이름"] || target_id

    # 아이템 확인 및 제거
    items = user["아이템"]
    items = items.is_a?(Array) ? items : items.to_s.split(',').map(&:strip)
    potion_name = "#{potion_type}물약"

    unless items.include?(potion_name)
      return { message: "#{user_name}: #{potion_name} 없음 (사용 실패)" }
    end

    items.delete_at(items.index(potion_name))

    # 체력 회복
    current_hp = (target["HP"] || 100).to_i
    vitality_stat = (target["체력"] || 0).to_i
    max_hp = 100 + (vitality_stat * 10)
    new_hp = [current_hp + heal_amount, max_hp].min

    @sheet_manager.update_user(user_id, { "아이템" => items.join(',') })
    @sheet_manager.update_user(target_id, { "HP" => new_hp })

    if user_id == target_id
      message = "#{user_name}이(가) #{potion_name} 사용! HP +#{heal_amount} (#{current_hp} → #{new_hp})"
    else
      message = "#{user_name}이(가) #{target_name}에게 #{potion_name} 사용! HP +#{heal_amount} (#{current_hp} → #{new_hp})"
    end

    { message: message }
  end

  # 공격 결과 계산 (방어/반격 최초 1회만 적용)
  def calculate_attack_result(attacker, attacker_id, defender, defender_id, state, is_cover_defense = false)
    attacker_name = attacker["이름"] || attacker_id
    defender_name = defender["이름"] || defender_id

    # 공격력 계산
    atk = (attacker["공격"] || 10).to_i
    atk_roll = rand(1..20)
    luck = (attacker["행운"] || 10).to_i

    crit_result = check_critical_hit(luck)
    atk_total = atk + atk_roll

    # 치명타
    if crit_result[:is_crit]
      atk_total = (atk_total * 1.5).to_i
    end

    # 방어력 계산
    def_stat = (defender["방어"] || 10).to_i
    def_roll = rand(1..20)
    def_total = def_stat + def_roll

    # 기본 데미지
    damage = [atk_total - def_total, 0].max

    # 방어/반격 (최초 1회만)
    guard_text = ""
    counter_text = ""
    counter_damage = 0
    display_def_total = def_total

    if state.dig(:guarded, defender_id) && !state.dig(:guarded_used, defender_id)
      # 방어 태세: 추가 D20 보너스
      guard_roll = rand(1..20)
      guard_total = def_stat + def_roll + guard_roll
      display_def_total = guard_total

      if guard_total >= atk_total
        damage = 0
        guard_text = " / 방어 성공!"
      else
        guard_text = " / 방어 실패"
      end

      state[:guarded_used] ||= {}
      state[:guarded_used][defender_id] = true
    end

    if state.dig(:counter, defender_id) && !state.dig(:counter_used, defender_id)
      state[:counter_used] ||= {}
      state[:counter_used][defender_id] = true

      # 반격: 피격 시 무조건 5 데미지 반환 (방어와 관계없이)
      counter_damage = 5
      counter_text = "\n#{defender_name}의 반격 발동! #{attacker_name} 반격 피해: 5"
    end

    # 대리 방어 표시
    cover_text = is_cover_defense ? " (대리 방어)" : ""

    message = "#{attacker_name}의 공격 vs #{defender_name}#{cover_text}\n"
    message += "공격: #{atk} + #{atk_roll} = #{atk + atk_roll}"
    message += " [치명타! x1.5]" if crit_result[:is_crit]
    message += "\n"
    message += "방어: #{def_stat} + #{def_roll} = #{display_def_total}#{guard_text}\n"
    message += "데미지: #{damage}#{counter_text}"

    {
      message: message,
      damage: damage,
      counter_damage: counter_damage
    }
  end
end
