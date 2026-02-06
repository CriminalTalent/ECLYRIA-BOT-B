# core/battle_engine.rb
# 체력 바 + 수치 표시 및 이모지 제거 버전

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

  def initialize(client, sheet_manager)
    @client = client
    @sheet_manager = sheet_manager
    
    # 시간 제한 체크를 위한 스레드 시작
    start_time_monitor
  end

  # 체력 바 생성
  def generate_hp_bar(current_hp, max_hp, bar_length = 10)
    return "█" * bar_length + " #{current_hp}/#{max_hp}" if current_hp >= max_hp
    return "░" * bar_length + " #{current_hp}/#{max_hp}" if current_hp <= 0 || max_hp <= 0
    
    filled_length = ((current_hp.to_f / max_hp.to_f) * bar_length).round
    empty_length = bar_length - filled_length
    
    "█" * filled_length + "░" * empty_length + " #{current_hp}/#{max_hp}"
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
    if state[:type] == "2v2" || state[:type] == "4v4"
      auto_defend_team_battle(battle_id, state)
    else
      auto_defend_single_battle(battle_id, state)
    end
  end

  def auto_defend_team_battle(battle_id, state)
    # 아직 행동하지 않은 플레이어들을 자동 방어 처리
    pending_players = []
    
    state[:participants].each do |player_id|
      unless state[:actions]&.key?(player_id)
        pending_players << player_id
      end
    end
    
    pending_players.each do |player_id|
      user = @sheet_manager.find_user(player_id)
      user_name = user ? (user["이름"] || player_id) : player_id
      
      # 자동 방어 등록
      register_action(player_id, :defend, player_id, battle_id)
      
      puts "[자동 방어] #{user_name} - 시간 초과로 자동 방어"
    end
    
    # 모든 플레이어가 행동했는지 확인하고 라운드 진행
    if all_players_ready?(state)
      execute_round(battle_id)
    end
  end

  def auto_defend_single_battle(battle_id, state)
    # 1v1이나 허수아비 전투의 자동 방어 처리
    current_user = state[:current_turn]
    user = @sheet_manager.find_user(current_user)
    user_name = user ? (user["이름"] || current_user) : current_user
    
    message = "시간 초과!\n"
    message += "#{user_name}이(가) 4분 내에 행동하지 않아 자동으로 방어합니다.\n"
    message += "━━━━━━━━━━━━━━━━━━\n"
    
    # 자동 방어 처리 후 다음 턴으로
    state[:guarded] ||= {}
    state[:guarded][current_user] = true
    
    next_turn_index = (state[:turn_order].index(state[:current_turn]) + 1) % state[:turn_order].length
    state[:current_turn] = state[:turn_order][next_turn_index]
    state[:last_action_time] = Time.now
    BattleState.update(battle_id, state)
    
    send_battle_message(battle_id, message + get_next_turn_message(state))
  end

  # 체력 총합으로 승부 결정
  def end_battle_by_hp_total(battle_id, state)
    message = "전투 시간 1시간 초과!\n"
    message += "━━━━━━━━━━━━━━━━━━\n"
    
    if state[:type] == "2v2" || state[:type] == "4v4"
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
    
    send_battle_message(battle_id, message)
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

  def get_user_max_hp(user_id)
    user = @sheet_manager.find_user(user_id)
    return 100 unless user
    100 + ((user["체력"] || 10).to_i * 10)
  end

  # 1:1 전투 시작 (기존 메소드명 유지)
  def start_battle(user1_id, user2_id, reply_status)
    # 이미 전투 중인지 확인
    if BattleState.find_by_participant(user1_id)
      user1_name = get_user_name(user1_id)
      @client.reply(reply_status, "#{user1_name}님은 이미 전투 중입니다.")
      return
    end
    
    if BattleState.find_by_participant(user2_id)
      user2_name = get_user_name(user2_id)
      @client.reply(reply_status, "#{user2_name}님은 이미 전투 중입니다.")
      return
    end

    user1 = @sheet_manager.find_user(user1_id)
    user2 = @sheet_manager.find_user(user2_id)
    unless user1 && user2
      @client.reply(reply_status, "참가자 중 등록되지 않은 사용자가 있습니다.")
      return
    end

    # 민첩성 필드 사용 (기존 코드와 호환)
    agi1 = (user1["민첩성"] || user1["민첩"] || 10).to_i + rand(1..20)
    agi2 = (user2["민첩성"] || user2["민첩"] || 10).to_i + rand(1..20)
    turn_order = agi1 >= agi2 ? [user1_id, user2_id] : [user2_id, user1_id]

    user1_name = user1["이름"] || user1_id
    user2_name = user2["이름"] || user2_id
    first_turn_name = turn_order[0] == user1_id ? user1_name : user2_name
    
    message = "━━━━━━━━━━━━━━━━━━\n"
    message += "전투 시작: #{user1_name} vs #{user2_name}\n"
    message += "선공: #{first_turn_name} (민첩 #{agi1 >= agi2 ? agi1 : agi2})\n"
    message += "━━━━━━━━━━━━━━━━━━\n"
    message += "제한시간: 1인당 4분, 전체 1시간\n"
    message += "━━━━━━━━━━━━━━━━━━\n"
    message += "#{first_turn_name}의 차례\n"
    message += "[공격/@타겟] [방어/@타겟] [반격] [물약사용] [도주]"

    result = @client.reply(reply_status, message)
    
    battle_id = BattleState.create({
      type: "pvp",
      participants: [user1_id, user2_id],
      turn_order: turn_order,
      current_turn: turn_order[0],
      guarded: {},
      counter: {},
      battle_start_time: Time.now,
      last_action_time: Time.now,
      reply_status: result,
      actions: {}
    })
    
    puts "[디버그] 1v1 전투 생성 완료: #{battle_id}"
  end

  # 2:2 전투 시작 (기존 메소드명 유지)
  def start_2v2_battle(team1, team2, reply_status)
    participants = team1 + team2
    
    # 이미 전투 중인지 확인
    participants.each do |id|
      if BattleState.find_by_participant(id)
        user_name = get_user_name(id)
        @client.reply(reply_status, "#{user_name}님은 이미 전투 중입니다.")
        return
      end
    end
    
    users = participants.map { |id| @sheet_manager.find_user(id) }
    if users.any?(&:nil?)
      @client.reply(reply_status, "참가자 중 등록되지 않은 사용자가 있습니다.")
      return
    end

    # 민첩성 기반 팀 순서 결정
    team1_agi = team1.sum { |id| 
      user = @sheet_manager.find_user(id)
      (user["민첩성"] || user["민첩"] || 10).to_i
    } + rand(1..20)
    
    team2_agi = team2.sum { |id|
      user = @sheet_manager.find_user(id)
      (user["민첩성"] || user["민첩"] || 10).to_i
    } + rand(1..20)
    
    first_team = team1_agi >= team2_agi ? :team1 : :team2
    
    names = users.map { |u| (u && u["이름"]) || "(미등록)" }
    first_team_name = first_team == :team1 ? "팀1" : "팀2"
    
    message = "━━━━━━━━━━━━━━━━━━\n"
    message += "2:2 팀 전투 시작\n"
    message += "팀1: #{names[0]}, #{names[1]}\n"
    message += "팀2: #{names[2]}, #{names[3]}\n"
    message += "선공 판정: 팀1(#{team1_agi}) vs 팀2(#{team2_agi})\n"
    message += "선공: #{first_team_name}\n"
    message += "━━━━━━━━━━━━━━━━━━\n"
    message += "제한시간: 1인당 4분, 전체 1시간\n"
    message += "━━━━━━━━━━━━━━━━━━\n"
    message += "라운드 1 - 모든 참가자는 행동을 선택하세요!\n"
    message += "[공격/@타겟] [방어/@타겟] [반격] [물약사용/@타겟] [도주]"

    result = @client.reply(reply_status, message)

    battle_id = BattleState.create({
      type: "2v2",
      participants: participants,
      teams: { team1: team1, team2: team2 },
      round: 1,
      actions: {},
      guarded: {},
      counter: {},
      battle_start_time: Time.now,
      last_action_time: Time.now,
      reply_status: result,
      first_team: first_team
    })
    
    puts "[디버그] 2v2 전투 생성 완료: #{battle_id}"
  end

  # 4:4 전투 시작 (기존 메소드명 유지)
  def start_4v4_battle(team1, team2, reply_status)
    participants = team1 + team2
    
    # 이미 전투 중인지 확인
    participants.each do |id|
      if BattleState.find_by_participant(id)
        user_name = get_user_name(id)
        @client.reply(reply_status, "#{user_name}님은 이미 전투 중입니다.")
        return
      end
    end
    
    users = participants.map { |id| @sheet_manager.find_user(id) }
    if users.any?(&:nil?)
      @client.reply(reply_status, "참가자 중 등록되지 않은 사용자가 있습니다.")
      return
    end

    # 민첩성 기반 팀 순서 결정
    team1_agi = team1.sum { |id| 
      user = @sheet_manager.find_user(id)
      (user["민첩성"] || user["민첩"] || 10).to_i
    } + rand(1..20)
    
    team2_agi = team2.sum { |id|
      user = @sheet_manager.find_user(id)
      (user["민첩성"] || user["민첩"] || 10).to_i
    } + rand(1..20)
    
    first_team = team1_agi >= team2_agi ? :team1 : :team2
    
    names = users.map { |u| (u && u["이름"]) || "(미등록)" }
    first_team_name = first_team == :team1 ? "팀1" : "팀2"
    
    message = "━━━━━━━━━━━━━━━━━━\n"
    message += "4:4 대규모 전투 시작\n"
    message += "팀1: #{names[0..3].join(', ')}\n"
    message += "팀2: #{names[4..7].join(', ')}\n"
    message += "선공 판정: 팀1(#{team1_agi}) vs 팀2(#{team2_agi})\n"
    message += "선공: #{first_team_name}\n"
    message += "━━━━━━━━━━━━━━━━━━\n"
    message += "제한시간: 1인당 4분, 전체 1시간\n"
    message += "━━━━━━━━━━━━━━━━━━\n"
    message += "라운드 1 - 모든 참가자는 행동을 선택하세요!\n"
    message += "[공격/@타겟] [방어/@타겟] [반격] [물약사용/@타겟] [도주]"

    result = @client.reply(reply_status, message)

    battle_id = BattleState.create({
      type: "4v4",
      participants: participants,
      teams: { team1: team1, team2: team2 },
      round: 1,
      actions: {},
      guarded: {},
      counter: {},
      battle_start_time: Time.now,
      last_action_time: Time.now,
      reply_status: result,
      first_team: first_team
    })
    
    puts "[디버그] 4v4 전투 생성 완료: #{battle_id}"
  end

  # 액션 등록 (기존 메소드명 유지)
  def register_action(user_id, action_type, target_id, battle_id, extra_data = nil)
    state = BattleState.get(battle_id)
    return false unless state
    
    # 시간 업데이트
    state[:last_action_time] = Time.now
    state[:actions] ||= {}
    state[:actions][user_id] = {
      action: action_type,
      target: target_id,
      extra: extra_data
    }
    
    BattleState.update(battle_id, state)
    
    user = @sheet_manager.find_user(user_id)
    user_name = user ? (user["이름"] || user_id) : user_id
    
    action_text = format_action_text(action_type, target_id, extra_data, user_name)
    
    case state[:type]
    when "pvp"
      handle_pvp_action(battle_id, state, action_text)
    when "2v2", "4v4"
      handle_team_action(battle_id, state, action_text)
    end
    
    true
  end

  private

  def format_action_text(action_type, target_id, extra_data, user_name)
    case action_type
    when :attack
      target_name = get_user_name(target_id)
      "#{user_name}이(가) #{target_name}을(를) 공격 준비"
    when :defend
      if target_id && target_id != user_name
        target_name = get_user_name(target_id)
        "#{user_name}이(가) #{target_name}을(를) 방어 준비"
      else
        "#{user_name}이(가) 방어 태세"
      end
    when :counter
      "#{user_name}이(가) 반격 태세"
    when :use_potion
      target_name = target_id ? get_user_name(target_id) : user_name
      potion_size = extra_data || "물약"
      "#{user_name}이(가) #{target_name}에게 #{potion_size} 사용 준비"
    else
      "#{user_name}이(가) 행동 선택"
    end
  end

  def handle_pvp_action(battle_id, state, action_text)
    message = "#{action_text}\n━━━━━━━━━━━━━━━━━━\n"
    
    if state[:actions].size >= 2
      # 양쪽 다 행동 선택 완료
      execute_pvp_round(battle_id)
    else
      # 상대방 턴
      next_player_id = state[:participants].find { |p| !state[:actions].key?(p) }
      if next_player_id
        next_player = @sheet_manager.find_user(next_player_id)
        next_player_name = next_player ? (next_player["이름"] || next_player_id) : next_player_id
        
        message += "#{next_player_name}의 차례\n"
        message += "[공격] [방어] [반격] [물약사용] [도주]"
      end
      
      send_battle_message(battle_id, message)
    end
  end

  def handle_team_action(battle_id, state, action_text)
    message = "#{action_text}\n━━━━━━━━━━━━━━━━━━\n"
    
    if all_players_ready?(state)
      # 모든 플레이어 행동 선택 완료
      execute_round(battle_id)
    else
      # 아직 선택하지 않은 플레이어들 표시
      pending = state[:participants].select { |p| !state[:actions].key?(p) }
      pending_names = pending.map { |p| get_user_name(p) }
      
      message += "대기 중: #{pending_names.join(', ')}\n"
      message += "[공격/@타겟] [방어/@타겟] [반격] [물약사용/@타겟] [도주]"
      
      send_battle_message(battle_id, message)
    end
  end

  def all_players_ready?(state)
    state[:participants].all? { |p| state[:actions].key?(p) }
  end

  def execute_round(battle_id)
    state = BattleState.get(battle_id)
    return unless state
    
    # 첫 번째 타래: 라운드 결과
    round_result = process_team_round_actions(state)
    
    # 두 번째 타래: 체력 현황 및 다음 라운드
    hp_result = process_team_hp_and_next_round(battle_id, state)
    
    # 스레드 형식으로 전송
    @client.reply_battle_thread(state[:reply_status], round_result, hp_result, state[:participants])
  end

  def process_team_round_actions(state)
    message = "라운드 #{state[:round]} 결과\n"
    message += "━━━━━━━━━━━━━━━━━━\n\n"
    
    # 방어/반격 상태 설정
    state[:actions].each do |user_id, action_data|
      case action_data[:action]
      when :defend
        state[:guarded] ||= {}
        if action_data[:target] && action_data[:target] != user_id
          state[:guarded][action_data[:target]] = true
        else
          state[:guarded][user_id] = true
        end
      when :counter
        state[:counter] ||= {}
        state[:counter][user_id] = true
      end
    end
    
    # 공격 처리
    state[:actions].each do |user_id, action_data|
      next unless action_data[:action] == :attack
      
      attacker = @sheet_manager.find_user(user_id)
      defender = @sheet_manager.find_user(action_data[:target])
      
      next unless attacker && defender
      
      result = calculate_attack_result(attacker, user_id, defender, action_data[:target], state)
      message += result[:message] + "\n\n"
      
      # HP 업데이트
      if result[:damage] > 0
        new_hp = [(defender["HP"] || 100).to_i - result[:damage], 0].max
        @sheet_manager.update_user(action_data[:target], { "HP" => new_hp })
      end
      
      if result[:counter_damage] > 0
        attacker_new_hp = [(attacker["HP"] || 100).to_i - result[:counter_damage], 0].max
        @sheet_manager.update_user(user_id, { "HP" => attacker_new_hp })
      end
    end
    
    message.strip
  end

  def process_team_hp_and_next_round(battle_id, state)
    message = "━━━━━━━━━━━━━━━━━━\n"
    message += "체력 현황\n"
    message += "━━━━━━━━━━━━━━━━━━\n"
    
    # 팀별 체력 정보
    team1_alive = 0
    team2_alive = 0
    
    message += "팀1:\n"
    state[:teams][:team1].each do |pid|
      u = @sheet_manager.find_user(pid)
      if u
        current_hp = (u["HP"] || 0).to_i
        max_hp = get_user_max_hp(pid)
        name = u["이름"] || pid
        status = current_hp > 0 ? "생존" : "전투불능"
        hp_bar = generate_hp_bar(current_hp, max_hp)
        message += "• #{name}: #{hp_bar} (#{status})\n"
        team1_alive += 1 if current_hp > 0
      end
    end
    
    message += "\n팀2:\n"
    state[:teams][:team2].each do |pid|
      u = @sheet_manager.find_user(pid)
      if u
        current_hp = (u["HP"] || 0).to_i
        max_hp = get_user_max_hp(pid)
        name = u["이름"] || pid
        status = current_hp > 0 ? "생존" : "전투불능"
        hp_bar = generate_hp_bar(current_hp, max_hp)
        message += "• #{name}: #{hp_bar} (#{status})\n"
        team2_alive += 1 if current_hp > 0
      end
    end
    
    message += "━━━━━━━━━━━━━━━━━━\n"
    
    # 승부 판정
    if team1_alive == 0
      message += "팀2 승리!"
      BattleState.clear(battle_id)
      return message
    elsif team2_alive == 0
      message += "팀1 승리!"
      BattleState.clear(battle_id)
      return message
    end
    
    # 다음 라운드 준비
    state[:round] += 1
    state[:actions] = {}
    state[:guarded] = {}
    state[:counter] = {}
    state[:last_action_time] = Time.now
    BattleState.update(battle_id, state)
    
    message += "\n라운드 #{state[:round]} 시작\n"
    message += "모든 참가자는 행동을 선택하세요!\n"
    message += "[공격/@타겟] [방어/@타겟] [반격] [물약사용/@타겟] [도주]"
    
    message
  end

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

  def send_battle_message(battle_id, message)
    state = BattleState.get(battle_id)
    return unless state && state[:reply_status]
    
    participants = state[:participants].reject { |p| p.include?("허수아비") }
    @client.reply(state[:reply_status], message)
  end

  def get_next_turn_message(state)
    if state[:current_turn]
      current_player = @sheet_manager.find_user(state[:current_turn])
      current_name = current_player ? (current_player["이름"] || state[:current_turn]) : state[:current_turn]
      
      "#{current_name}의 차례\n[공격] [방어] [반격] [물약사용] [도주]"
    else
      "다음 행동을 선택하세요."
    end
  end
end
