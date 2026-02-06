# core/battle_engine.rb
# 개선된 전투 엔진 - 시간 제한, 자동 방어, 스레드 출력 포함

require_relative 'battle_state'

class BattleEngine
  DUMMY_STATS = {
    "하" => { hp: 30, atk: 2, def: 1, agi: 2, luck: 5 },
    "중" => { hp: 50, atk: 3, def: 2, agi: 3, luck: 8 },
    "상" => { hp: 70, atk: 4, def: 3, agi: 4, luck: 12 }
  }

  # 시간 제한 설정
  TURN_TIME_LIMIT = 4 * 60  # 4분 (240초)
  BATTLE_TIME_LIMIT = 60 * 60  # 1시간 (3600초)

  def initialize(mastodon_client, sheet_manager)
    @mastodon_client = mastodon_client
    @sheet_manager   = sheet_manager
    
    # 시간 제한 체크를 위한 스레드 시작
    start_time_monitor
  end

  # 시간 제한 모니터링 스레드
  def start_time_monitor
    @time_monitor_thread = Thread.new do
      loop do
        sleep 30  # 30초마다 체크
        check_all_battles_timeout
      rescue => e
        puts "[시간 모니터 오류] #{e.message}"
      end
    end
  end

  # 모든 전투의 시간 제한 체크
  def check_all_battles_timeout
    BattleState.get_all_battles.each do |battle_id, state|
      next unless state && state[:participants]
      
      current_time = Time.now
      
      # 전체 전투 시간 제한 체크 (1시간)
      if current_time - state[:battle_start_time] > BATTLE_TIME_LIMIT
        end_battle_by_hp_total(battle_id, state)
        next
      end
      
      # 턴 시간 제한 체크 (4분)
      if state[:last_action_time] && 
         current_time - state[:last_action_time] > TURN_TIME_LIMIT
        auto_defend_timeout(battle_id, state)
      end
    end
  end

  # 시간 초과로 자동 방어
  def auto_defend_timeout(battle_id, state)
    current_user = state[:current_turn]
    user = @sheet_manager.find_user(current_user)
    user_name = user ? (user["이름"] || current_user) : current_user
    
    message = "⏰ 시간 초과!\n"
    message += "#{user_name}이(가) 4분 내에 행동하지 않아 자동으로 방어합니다.\n"
    message += "━━━━━━━━━━━━━━━━━━\n"
    
    # 자동 방어 처리
    if state[:type] == "2v2"
      handle_2v2_action(current_user, :defend, nil, battle_id, state, true)
    else
      # 1v1 또는 허수아비 전투
      state[:guarded] ||= {}
      state[:guarded][current_user] = true
      
      # 다음 턴으로
      next_turn_index = (state[:turn_order].index(state[:current_turn]) + 1) % state[:turn_order].length
      state[:current_turn] = state[:turn_order][next_turn_index]
      state[:last_action_time] = Time.now
      BattleState.update(battle_id, state)
      
      if state[:current_turn].to_s.include?("허수아비")
        difficulty = state[:difficulty]
        perform_dummy_attack(current_user, user, difficulty, battle_id, state, message)
      else
        next_player = @sheet_manager.find_user(state[:current_turn])
        next_player_name = next_player ? (next_player["이름"] || state[:current_turn]) : state[:current_turn]
        
        message += "#{next_player_name}의 차례\n"
        message += get_action_options(state)
        
        reply_to_battle_thread(message, battle_id, state)
      end
    end
  end

  # 체력 총합으로 승부 결정
  def end_battle_by_hp_total(battle_id, state)
    message = "⏰ 전투 시간 1시간 초과!\n"
    message += "━━━━━━━━━━━━━━━━━━\n"
    
    if state[:type] == "2v2"
      team1_hp = calculate_team_hp(state[:teams][:team1])
      team2_hp = calculate_team_hp(state[:teams][:team2])
      
      message += "팀별 체력 총합:\n"
      message += "팀1: #{team1_hp}HP\n"
      message += "팀2: #{team2_hp}HP\n"
      message += "━━━━━━━━━━━━━━━━━━\n"
      
      if team1_hp > team2_hp
        message += "팀1 승리! (체력 총합)"
      elsif team2_hp > team1_hp
        message += "팀2 승리! (체력 총합)"
      else
        message += "무승부!"
      end
    else
      # 1v1 전투
      user1_hp = get_user_hp(state[:participants][0])
      user2_hp = get_user_hp(state[:participants][1])
      
      message += "체력 현황:\n"
      message += "#{get_user_name(state[:participants][0])}: #{user1_hp}HP\n"
      message += "#{get_user_name(state[:participants][1])}: #{user2_hp}HP\n"
      message += "━━━━━━━━━━━━━━━━━━\n"
      
      if user1_hp > user2_hp
        message += "#{get_user_name(state[:participants][0])} 승리! (체력 총합)"
      elsif user2_hp > user1_hp
        message += "#{get_user_name(state[:participants][1])} 승리! (체력 총합)"
      else
        message += "무승부!"
      end
    end
    
    reply_to_battle_thread(message, battle_id, state)
    BattleState.clear(battle_id)
  end

  # 팀 체력 계산
  def calculate_team_hp(team_members)
    team_members.sum do |member_id|
      get_user_hp(member_id)
    end
  end

  def get_user_hp(user_id)
    user = @sheet_manager.find_user(user_id)
    user ? [(user["HP"] || 0).to_i, 0].max : 0
  end

  def get_user_name(user_id)
    user = @sheet_manager.find_user(user_id)
    user ? (user["이름"] || user_id) : user_id
  end

  def start_1v1(user1_id, user2_id, reply_status)
    # 이미 전투 중인지 확인
    if BattleState.find_by_user(user1_id)
      user1_name = get_user_name(user1_id)
      @mastodon_client.reply(reply_status, "#{user1_name}님은 이미 전투 중입니다.")
      return
    end
    
    if BattleState.find_by_user(user2_id)
      user2_name = get_user_name(user2_id)
      @mastodon_client.reply(reply_status, "#{user2_name}님은 이미 전투 중입니다.")
      return
    end

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
    message += "⏰ 제한시간: 1인당 4분, 전체 1시간\n"
    message += "━━━━━━━━━━━━━━━━━━\n"
    message += "#{first_turn_name}의 차례\n"
    message += "[공격] [방어] [반격] [물약사용] [도주]"

    result = @mastodon_client.reply_with_mentions(reply_status, message, [user1_id, user2_id])
    
    battle_id = BattleState.create([user1_id, user2_id], {
      type: "1v1",
      participants: [user1_id, user2_id],
      turn_order: turn_order,
      current_turn: turn_order[0],
      guarded: {},
      counter: {},
      battle_start_time: Time.now,
      last_action_time: Time.now,
      reply_status: result || reply_status
    })
    
    puts "[디버그] 1v1 전투 생성 완료: #{battle_id}"
  end

  def start_2v2(user1_id, user2_id, user3_id, user4_id, reply_status)
    ids = [user1_id, user2_id, user3_id, user4_id]
    
    # 이미 전투 중인지 확인
    ids.each do |id|
      if BattleState.find_by_user(id)
        user_name = get_user_name(id)
        @mastodon_client.reply(reply_status, "#{user_name}님은 이미 전투 중입니다.")
        return
      end
    end
    
    users = ids.map { |id| @sheet_manager.find_user(id) }
    if users.any?(&:nil?)
      @mastodon_client.reply(reply_status, "참가자 중 등록되지 않은 사용자가 있습니다.")
      return
    end

    team1_agi = (users[0]["민첩"] || 10).to_i + (users[1]["민첩"] || 10).to_i + rand(1..20)
    team2_agi = (users[2]["민첩"] || 10).to_i + (users[3]["민첩"] || 10).to_i + rand(1..20)
    
    team1_order = [0, 1].sort_by { |i| -(users[i]["민첩"] || 10).to_i }.map { |i| ids[i] }
    team2_order = [2, 3].sort_by { |i| -(users[i]["민첩"] || 10).to_i }.map { |i| ids[i] }
    
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
    message += "⏰ 제한시간: 1인당 4분, 전체 1시간\n"
    message += "━━━━━━━━━━━━━━━━━━\n"
    message += "라운드 1 시작\n"
    
    first_player = @sheet_manager.find_user(turn_order[0])
    first_player_name = first_player["이름"] || turn_order[0]
    message += "#{first_player_name}의 차례\n"
    message += "[공격/@타겟] [방어/@타겟] [반격] [물약사용] [도주]"

    result = @mastodon_client.reply_with_mentions(reply_status, message, ids)

    battle_id = BattleState.create(ids, {
      type: "2v2",
      participants: ids,
      teams: { team1: [user1_id, user2_id], team2: [user3_id, user4_id] },
      turn_order: turn_order,
      current_turn: turn_order[0],
      round: 1,
      turn_index: 0,
      actions_queue: [],
      guarded: {},
      counter: {},
      battle_start_time: Time.now,
      last_action_time: Time.now,
      reply_status: result || reply_status
    })
    
    puts "[디버그] 2v2 전투 생성 완료: #{battle_id}"
  end

  def start_dummy_battle(user_id, difficulty, reply_status)
    # 이미 전투 중인지 확인
    if BattleState.find_by_user(user_id)
      user_name = get_user_name(user_id)
      @mastodon_client.reply(reply_status, "#{user_name}님은 이미 전투 중입니다.")
      return
    end
    
    user = @sheet_manager.find_user(user_id)
    unless user
      @mastodon_client.reply(reply_status, "등록되지 않은 사용자입니다.")
      return
    end

    dummy_id = "허수아비_#{difficulty}"
    user_agi = (user["민첩"] || 10).to_i + rand(1..20)
    dummy_agi = DUMMY_STATS[difficulty][:agi] + rand(1..20)
    turn_order = user_agi >= dummy_agi ? [user_id, dummy_id] : [dummy_id, user_id]

    user_name = user["이름"] || user_id
    first_turn_name = turn_order[0] == user_id ? user_name : "허수아비(#{difficulty})"

    message = "━━━━━━━━━━━━━━━━━━\n"
    message += "허수아비 전투 시작: #{user_name} vs 허수아비(#{difficulty})\n"
    message += "허수아비 스탯 - HP:#{DUMMY_STATS[difficulty][:hp]} ATK:#{DUMMY_STATS[difficulty][:atk]} DEF:#{DUMMY_STATS[difficulty][:def]}\n"
    message += "선공: #{first_turn_name}\n"
    message += "━━━━━━━━━━━━━━━━━━\n"
    message += "⏰ 제한시간: 1인당 4분, 전체 1시간\n"
    message += "━━━━━━━━━━━━━━━━━━\n"
    
    if turn_order[0] == user_id
      message += "#{user_name}의 차례\n"
      message += "[공격] [방어] [반격] [물약사용] [도주]"
    else
      message += "허수아비가 먼저 공격합니다!"
    end

    result = @mastodon_client.reply_with_mentions(reply_status, message, [user_id])

    battle_id = BattleState.create([user_id], {
      type: "dummy",
      participants: [user_id],
      turn_order: turn_order,
      current_turn: turn_order[0],
      difficulty: difficulty,
      dummy_hp: DUMMY_STATS[difficulty][:hp],
      guarded: {},
      counter: {},
      battle_start_time: Time.now,
      last_action_time: Time.now,
      reply_status: result || reply_status
    })

    # 허수아비가 선공이면 바로 공격
    if turn_order[0] == dummy_id
      state = BattleState.get(battle_id)
      perform_dummy_attack(user_id, user, difficulty, battle_id, state, "")
    end
    
    puts "[디버그] 허수아비 전투 생성 완료: #{battle_id}"
  end

  # 기존 메소드들 (attack, defend, counter, flee)는 시간 업데이트 추가
  def attack(user_id, target_id = nil)
    battle_id = BattleState.find_battle_id_by_user(user_id)
    state = BattleState.get(battle_id)
    
    # 시간 업데이트
    state[:last_action_time] = Time.now
    BattleState.update(battle_id, state)
    
    return unless state && state[:current_turn].to_s == user_id.to_s

    attacker = @sheet_manager.find_user(user_id)
    return unless attacker

    if state[:type] == "2v2"
      unless target_id
        reply_to_battle_thread("2:2 전투에서는 [공격/@타겟] 형식으로 타겟을 지정해야 합니다.", battle_id, state)
        return
      end
      handle_2v2_action(user_id, :attack, target_id, battle_id, state)
    elsif state[:type] == "dummy"
      perform_player_attack_on_dummy(user_id, attacker, battle_id, state)
    else
      target_id ||= find_opponent(user_id, state)
      perform_player_attack(user_id, attacker, target_id, battle_id, state)
    end
  end

  def defend(user_id, target_id = nil)
    battle_id = BattleState.find_battle_id_by_user(user_id)
    state = BattleState.get(battle_id)
    
    # 시간 업데이트
    state[:last_action_time] = Time.now
    BattleState.update(battle_id, state)
    
    return unless state && state[:current_turn].to_s == user_id.to_s

    if state[:type] == "2v2"
      if target_id
        handle_2v2_action(user_id, :defend_target, target_id, battle_id, state)
      else
        handle_2v2_action(user_id, :defend, nil, battle_id, state)
      end
      return
    end

    state[:guarded] ||= {}
    state[:guarded][user_id] = true
    BattleState.update(battle_id, state)

    name = get_user_name(user_id)
    
    message = "#{name}은(는) 방어 태세!\n"
    message += "(다음 공격 시 방어 주사위 2회 판정)\n"
    message += "━━━━━━━━━━━━━━━━━━\n"

    state[:current_turn] = state[:turn_order][(state[:turn_order].index(state[:current_turn]) + 1) % state[:turn_order].length]
    BattleState.update(battle_id, state)
    
    if state[:current_turn].to_s.include?("허수아비")
      difficulty = state[:difficulty]
      user = @sheet_manager.find_user(user_id)
      perform_dummy_attack(user_id, user, difficulty, battle_id, state, message)
    else
      next_player = @sheet_manager.find_user(state[:current_turn])
      next_player_name = next_player ? (next_player["이름"] || state[:current_turn]) : state[:current_turn]
      
      message += "#{next_player_name}의 차례\n"
      message += get_action_options(state)
      
      reply_to_battle_thread(message, battle_id, state)
    end
  end

  def counter(user_id)
    battle_id = BattleState.find_battle_id_by_user(user_id)
    state = BattleState.get(battle_id)
    
    # 시간 업데이트
    state[:last_action_time] = Time.now
    BattleState.update(battle_id, state)
    
    return unless state && state[:current_turn].to_s == user_id.to_s

    if state[:type] == "2v2"
      handle_2v2_action(user_id, :counter, nil, battle_id, state)
      return
    end

    state[:counter] ||= {}
    state[:counter][user_id] = true
    BattleState.update(battle_id, state)

    name = get_user_name(user_id)
    
    message = "#{name}은(는) 반격 태세!\n"
    message += "(상대의 공격을 받으면 5의 고정 피해)\n"
    message += "━━━━━━━━━━━━━━━━━━\n"

    state[:current_turn] = state[:turn_order][(state[:turn_order].index(state[:current_turn]) + 1) % state[:turn_order].length]
    BattleState.update(battle_id, state)
    
    if state[:current_turn].to_s.include?("허수아비")
      difficulty = state[:difficulty]
      user = @sheet_manager.find_user(user_id)
      perform_dummy_attack(user_id, user, difficulty, battle_id, state, message)
    else
      next_player = @sheet_manager.find_user(state[:current_turn])
      next_player_name = next_player ? (next_player["이름"] || state[:current_turn]) : state[:current_turn]
      
      message += "#{next_player_name}의 차례\n"
      message += get_action_options(state)
      
      reply_to_battle_thread(message, battle_id, state)
    end
  end

  def flee(user_id)
    battle_id = BattleState.find_battle_id_by_user(user_id)
    state = BattleState.get(battle_id)
    
    unless state
      @mastodon_client.post("진행 중인 전투가 없습니다.", visibility: 'public')
      return
    end

    unless state[:participants].include?(user_id)
      name = get_user_name(user_id)
      @mastodon_client.post("#{name}은(는) 이 전투의 참가자가 아닙니다.", visibility: 'public')
      return
    end

    user = @sheet_manager.find_user(user_id)
    name = (user || {})["이름"] || user_id
    luck = (user["행운"] || 10).to_i
    agility = (user["민첩"] || 10).to_i
    
    flee_roll = rand(1..20)
    flee_total = flee_roll + luck + agility
    flee_difficulty = 25
    
    if flee_total >= flee_difficulty
      message = "#{name}이(가) 전투에서 도주했습니다!\n"
      message += "판정: #{flee_roll} + 행운 #{luck} + 민첩 #{agility} = #{flee_total} (난이도 #{flee_difficulty})\n"
      message += "전투 종료"
      
      reply_to_battle_thread(message, battle_id, state)
      BattleState.clear(battle_id)
    else
      message = "#{name}의 도주 실패!\n"
      message += "판정: #{flee_roll} + 행운 #{luck} + 민첩 #{agility} = #{flee_total} (난이도 #{flee_difficulty})\n"
      message += "턴을 소비했습니다.\n"
      message += "━━━━━━━━━━━━━━━━━━\n"
      
      # 시간 업데이트
      state[:last_action_time] = Time.now
      state[:current_turn] = state[:turn_order][(state[:turn_order].index(state[:current_turn]) + 1) % state[:turn_order].length]
      BattleState.update(battle_id, state)
      
      if state[:current_turn].to_s.include?("허수아비")
        difficulty = state[:difficulty]
        perform_dummy_attack(user_id, user, difficulty, battle_id, state, message)
      else
        next_player = @sheet_manager.find_user(state[:current_turn])
        next_player_name = next_player ? (next_player["이름"] || state[:current_turn]) : state[:current_turn]
        
        message += "#{next_player_name}의 차례\n"
        message += get_action_options(state)
        
        reply_to_battle_thread(message, battle_id, state)
      end
    end
  end

  private

  # 2v2 액션 처리 (자동 방어 옵션 추가)
  def handle_2v2_action(user_id, action_type, target_id, battle_id, state, auto_action = false)
    if action_type == :attack
      unless target_id
        reply_to_battle_thread("2:2 전투에서는 [공격/@타겟] 형식으로 타겟을 지정해야 합니다.", battle_id, state)
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
    end

    state[:actions_queue] ||= []
    state[:actions_queue] << {
      user_id: user_id,
      action: action_type,
      target: target_id
    }

    user = @sheet_manager.find_user(user_id)
    user_name = user["이름"] || user_id
    
    action_text = case action_type
                  when :attack
                    target_name = get_user_name(target_id)
                    auto_action ? "#{user_name}이(가) 시간 초과로 자동 방어 (#{target_name} 공격 예정이었음)" : "#{user_name}이(가) #{target_name}을(를) 공격 준비"
                  when :defend
                    auto_action ? "#{user_name}이(가) 시간 초과로 자동 방어" : "#{user_name}이(가) 방어 태세"
                  when :defend_target
                    target_name = get_user_name(target_id)
                    "#{user_name}이(가) #{target_name}을(를) 방어 준비"
                  when :counter
                    "#{user_name}이(가) 반격 태세"
                  end
    
    message = "#{action_text}\n"
    message += "━━━━━━━━━━━━━━━━━━\n"

    state[:turn_index] += 1
    state[:last_action_time] = Time.now
    BattleState.update(battle_id, state)
    
    if state[:turn_index] >= 4
      process_2v2_round_complete(battle_id, state, message)
    else
      state[:current_turn] = state[:turn_order][state[:turn_index]]
      BattleState.update(battle_id, state)
      
      next_player = @sheet_manager.find_user(state[:current_turn])
      next_player_name = next_player["이름"] || state[:current_turn]
      
      message += "#{next_player_name}의 차례\n"
      message += "[공격/@타겟] [방어/@타겟] [반격] [물약사용] [도주]"
      
      reply_to_battle_thread(message, battle_id, state)
    end
  end

  # 2v2 라운드 완료 처리 (개선됨)
  def process_2v2_round_complete(battle_id, state, prefix_message)
    # 첫 번째 타래: 라운드 결과
    message1 = prefix_message
    message1 += "\n라운드 #{state[:round]} 결과\n"
    message1 += "━━━━━━━━━━━━━━━━━━\n\n"

    # 방어/반격 상태 설정
    state[:actions_queue].each do |action|
      if action[:action] == :defend
        state[:guarded] ||= {}
        state[:guarded][action[:user_id]] = true
      elsif action[:action] == :defend_target
        state[:guarded] ||= {}
        state[:guarded][action[:target]] = true
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
      message1 += result[:message] + "\n\n"
      
      if result[:damage] > 0
        new_hp = [(defender["HP"] || 100).to_i - result[:damage], 0].max
        @sheet_manager.update_user(action[:target], { hp: new_hp })
      end
      
      if result[:counter_damage] > 0
        attacker_new_hp = [(attacker["HP"] || 100).to_i - result[:counter_damage], 0].max
        @sheet_manager.update_user(action[:user_id], { hp: attacker_new_hp })
      end
    end

    # 첫 번째 타래 전송
    reply_to_battle_thread(message1, battle_id, state)

    # 두 번째 타래: 체력 현황 및 다음 라운드
    message2 = "━━━━━━━━━━━━━━━━━━\n"
    message2 += "체력 현황\n"
    message2 += "━━━━━━━━━━━━━━━━━━\n"
    
    # 팀별 체력 정보
    team1_members = state[:teams][:team1]
    team2_members = state[:teams][:team2]
    
    message2 += "팀1:\n"
    team1_alive = 0
    team1_members.each do |pid|
      u = @sheet_manager.find_user(pid)
      if u
        hp = (u["HP"] || 0).to_i
        name = u["이름"] || pid
        status = hp > 0 ? "생존" : "전투불능"
        message2 += "• #{name}: #{hp}HP (#{status})\n"
        team1_alive += 1 if hp > 0
      end
    end
    
    message2 += "\n팀2:\n"
    team2_alive = 0
    team2_members.each do |pid|
      u = @sheet_manager.find_user(pid)
      if u
        hp = (u["HP"] || 0).to_i
        name = u["이름"] || pid
        status = hp > 0 ? "생존" : "전투불능"
        message2 += "• #{name}: #{hp}HP (#{status})\n"
        team2_alive += 1 if hp > 0
      end
    end
    
    message2 += "━━━━━━━━━━━━━━━━━━\n"

    # 승부 판정
    if team1_alive == 0
      message2 += "팀2 승리!"
      reply_to_battle_thread(message2, battle_id, state)
      BattleState.clear(battle_id)
      return
    elsif team2_alive == 0
      message2 += "팀1 승리!"
      reply_to_battle_thread(message2, battle_id, state)
      BattleState.clear(battle_id)
      return
    end

    # 다음 라운드 준비
    state[:round] += 1
    state[:turn_index] = 0
    state[:actions_queue] = []
    state[:guarded] = {}
    state[:counter] = {}
    state[:current_turn] = state[:turn_order][0]
    state[:last_action_time] = Time.now
    BattleState.update(battle_id, state)

    first_player = @sheet_manager.find_user(state[:current_turn])
    first_player_name = first_player["이름"] || state[:current_turn]
    
    message2 += "\n라운드 #{state[:round]} 시작\n"
    message2 += "#{first_player_name}의 차례\n"
    message2 += "[공격/@타겟] [방어/@타겟] [반격] [물약사용] [도주]"

    reply_to_battle_thread(message2, battle_id, state)
  end

  # 나머지 기존 메소드들 (calculate_attack_result, perform_player_attack 등)은 유지
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
    counter_damage = 0
    
    if state.dig(:guarded, defender_id)
      guard_roll = rand(1..20)
      guard_total = def_stat + guard_roll
      
      if guard_total >= atk_total
        damage = 0
        guard_text = " / 방어 성공!"
      else
        guard_text = " / 방어 실패"
      end
    end
    
    if state.dig(:counter, defender_id) && damage > 0
      counter_damage = 5
      guard_text += " / 반격 발동!"
    end

    message = "#{attacker_name}의 공격 vs #{defender_name}\n"
    message += "공격: #{atk_roll} + #{atk} = #{atk_total}"
    message += " [치명타!]" if crit_result[:is_crit]
    message += "\n방어: #{def_roll} + #{def_stat} = #{def_total}"
    message += guard_text
    message += "\n데미지: #{damage}"
    message += "\n반격 피해: #{counter_damage}" if counter_damage > 0

    {
      message: message,
      damage: damage,
      counter_damage: counter_damage
    }
  end

  def check_critical_hit(luck)
    crit_chance = [luck / 2, 50].min
    roll = rand(1..100)
    
    if roll <= crit_chance
      return { is_crit: true, roll: roll, chance: crit_chance }
    else
      return { is_crit: false, roll: roll, chance: crit_chance }
    end
  end

  def perform_player_attack(user_id, attacker, target_id, battle_id, state)
    # 기존 로직 유지하되 시간 업데이트만 추가
    state[:last_action_time] = Time.now
    BattleState.update(battle_id, state)
    # ... 나머지 기존 로직
  end

  def perform_player_attack_on_dummy(user_id, attacker, battle_id, state)
    # 기존 로직 유지하되 시간 업데이트만 추가
    state[:last_action_time] = Time.now
    BattleState.update(battle_id, state)
    # ... 나머지 기존 로직
  end

  def perform_dummy_attack(user_id, user, difficulty, battle_id, state, prefix_message)
    # 기존 로직 유지하되 시간 업데이트만 추가
    state[:last_action_time] = Time.now
    BattleState.update(battle_id, state)
    # ... 나머지 기존 로직
  end

  def get_action_options(state)
    if state[:type] == "2v2"
      my_team = state[:teams][:team1].include?(state[:current_turn]) ? :team1 : :team2
      enemy_team = my_team == :team1 ? :team2 : :team1
      allies = state[:teams][my_team].select do |pid|
        u = @sheet_manager.find_user(pid)
        u && (u["HP"] || 100).to_i > 0
      end
      enemies = state[:teams][enemy_team].select do |pid|
        u = @sheet_manager.find_user(pid)
        u && (u["HP"] || 100).to_i > 0
      end
      
      options = "[공격/@타겟] [방어/@타겟] [반격] [물약사용] [도주]\n"
      options += "공격 타겟: " + enemies.map { |e| "@#{e}" }.join(", ") + "\n"
      options += "방어 타겟: " + allies.map { |a| "@#{a}" }.join(", ")
      return options
    else
      return "[공격] [방어] [반격] [물약사용] [도주]"
    end
  end

  def reply_to_battle_thread(message, battle_id, state)
    return nil unless state[:reply_status]
    participants = state[:participants].reject { |p| p.include?("허수아비") }
    @mastodon_client.reply_with_mentions(state[:reply_status], message, participants)
  end

  def find_opponent(user_id, state)
    if state[:type] == "1v1"
      state[:participants].find { |p| p != user_id }
    elsif state[:type] == "2v2"
      my_team = state[:teams][:team1].include?(user_id) ? :team1 : :team2
      enemy_team = (my_team == :team1 ? :team2 : :team1)
      alive = state[:teams][enemy_team].select do |pid|
        u = @sheet_manager.find_user(pid)
        u && (u["HP"] || 0).to_i > 0
      end
      alive.empty? ? nil : alive.sample
    end
  end
end
