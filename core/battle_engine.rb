# core/battle_engine.rb
require 'securerandom'

require_relative 'battle_state'
require_relative '../sheet_manager'

class BattleEngine
  def initialize(client, sheet_manager)
    @client = client
    @sheet_manager = sheet_manager
  end

  # 1:1 전투 시작
  def start_battle(user_id, opponent_id, reply_status)
    participants = [user_id, opponent_id]

    # 선공 결정 (민첩성 + D20)
    user = @sheet_manager.find_user(user_id)
    opponent = @sheet_manager.find_user(opponent_id)

    user_dex = (user["민첩성"] || 10).to_i
    opponent_dex = (opponent["민첩성"] || 10).to_i

    user_init = user_dex + rand(1..20)
    opponent_init = opponent_dex + rand(1..20)

        # 턴 순서 결정 (높은 순서대로)
    turn_order = [[user_id, user_init], [opponent_id, opponent_init]]
                  .sort_by { |_, init| -init }
                  .map { |id, _| id }

    # visibility 가져오기
    visibility = get_visibility(reply_status)
    status_uri = get_status_uri(reply_status)

    # 전투 상태 생성
    battle_id = BattleState.create(
      participants,
      "pvp",
      status_uri,
      status_uri,
      visibility
    )

    state = BattleState.get(battle_id)
    state[:turn_order] = turn_order
    state[:current_turn] = turn_order.first
    state[:original_status] = reply_status
    BattleState.update(battle_id, state)


        user_name = user["이름"] || user_id
    opponent_name = opponent["이름"] || opponent_id

    # 참가자 태그 (ID와 이름)
    message = "@#{user_id} @#{opponent_id}\n\n"
    message += "전투 시작!\n\n"
    message += "#{user_name} (민첩: #{user_dex} + #{user_init - user_dex}) = #{user_init}\n"
    message += "#{opponent_name} (민첩: #{opponent_dex} + #{opponent_init - opponent_dex}) = #{opponent_init}\n\n"
    message += "턴 순서: #{turn_order.map { |id| get_user_name(id) }.join(' → ')}\n\n"
    message += show_all_hp(state)

    first_name = get_user_name(turn_order.first)
    message += "\n\n@#{turn_order.first} (#{first_name})\n"
    message += "[공격] [방어] [반격] [물약사용/크기]"

    reply_to_status(reply_status, message, visibility)
  end

  # 2:2 전투 시작
  def start_2v2_battle(team1, team2, reply_status)
    participants = team1 + team2

    team1_dex_sum = team1.sum do |p|
      user = @sheet_manager.find_user(p)
      (user["민첩성"] || 10).to_i
    end

    team2_dex_sum = team2.sum do |p|
      user = @sheet_manager.find_user(p)
      (user["민첩성"] || 10).to_i
    end

    team1_init = team1_dex_sum + rand(1..20)
    team2_init = team2_dex_sum + rand(1..20)

    first_team = team1_init >= team2_init ? team1 : team2
    second_team = first_team == team1 ? team2 : team1

    first_team_sorted = first_team.sort_by do |p|
      user = @sheet_manager.find_user(p)
      -(user["민첩성"] || 10).to_i
    end

    second_team_sorted = second_team.sort_by do |p|
      user = @sheet_manager.find_user(p)
      -(user["민첩성"] || 10).to_i
    end

    turn_order = first_team_sorted + second_team_sorted

      # visibility 및 status URI
    visibility = get_visibility(reply_status)
    status_uri = get_status_uri(reply_status)

    battle_id = BattleState.create(
      participants,
      "2v2",
      status_uri,
      status_uri,
      visibility
    )

    state = BattleState.get(battle_id)
    state[:teams] = {
      team1: team1,
      team2: team2
    }
    state[:turn_order] = turn_order
    state[:current_turn] = turn_order.first
    state[:original_status] = reply_status
    state[:protect] = {}
    BattleState.update(battle_id, state)

    team1_name = "불사조 기사단"
    team2_name = "이그드라실"

    tags = participants.map { |p| "@#{p}" }.join(" ")
    message = "#{tags}\n\n"
    message += "2:2 전투 시작!\n\n"
    message += "#{team1_name}: #{team1.map { |id| get_user_name(id) }.join(', ')}\n"
    message += "#{team2_name}: #{team2.map { |id| get_user_name(id) }.join(', ')}\n\n"
    message += "턴 순서: #{turn_order.map { |id| get_user_name(id) }.join(' → ')}\n\n"
    message += show_all_hp(state)

        first_name = get_user_name(turn_order.first)
    message += "\n\n@#{turn_order.first} (#{first_name})\n"
    message += "[공격/@타겟] [방어/@아군] [반격] [물약사용/크기/@아군]"

    reply_to_status(reply_status, message, visibility)
  end

  # 4:4 전투 시작
  def start_4v4_battle(team1, team2, reply_status)
    participants = team1 + team2

    # 팀별 민첩성 합산
    team1_dex_sum = team1.sum { |id| (@sheet_manager.find_user(id)["민첩성"] || 10).to_i }
    team2_dex_sum = team2.sum { |id| (@sheet_manager.find_user(id)["민첩성"] || 10).to_i }

    team1_init = team1_dex_sum + rand(1..20)
    team2_init = team2_dex_sum + rand(1..20)

    first_team, second_team = team1_init >= team2_init ? [team1, team2] : [team2, team1]

    first_team_sorted = first_team.sort_by { |id| -(@sheet_manager.find_user(id)["민첩성"] || 10).to_i }
    second_team_sorted = second_team.sort_by { |id| -(@sheet_manager.find_user(id)["민첩성"] || 10).to_i }
    turn_order = first_team_sorted + second_team_sorted

        # visibility 가져오기
    visibility = get_visibility(reply_status)
    status_uri = get_status_uri(reply_status)

    battle_id = BattleState.create(
      participants,
      "4v4",
      status_uri,
      status_uri,
      visibility
    )

    state = BattleState.get(battle_id)
    state[:teams] = { team1: team1, team2: team2 }
    state[:turn_order] = turn_order
    state[:current_turn] = turn_order.first
    state[:original_status] = reply_status
    state[:protect] = {}
    BattleState.update(battle_id, state)

    # 참가자 태그
    tags = participants.map { |p| "@#{p}" }.join(" ")
    message = "#{tags}\n\n"
    message += "4:4 전투 시작!\n\n"
    message += "팀1: 불사조 기사단 (#{team1.map { |id| get_user_name(id) }.join(', ')})\n"
    message += "팀2: 이그드라실 (#{team2.map { |id| get_user_name(id) }.join(', ')})\n\n"
    message += "턴 순서: #{turn_order.map { |id| get_user_name(id) }.join(' → ')}\n\n"
    message += show_all_hp(state)

    first_name = get_user_name(turn_order.first)
    message += "\n\n@#{turn_order.first} (#{first_name})\n"
    message += "[공격/@타겟] [방어/@아군] [반격] [물약사용/크기/@아군]"

    reply_to_status(reply_status, message, visibility)
  end

    # 액션 등록
  def register_action(user_id, action_type, target_id, battle_id, potion_size = nil)
    state = BattleState.get(battle_id)
    return unless state

    # 현재 턴 확인
    if state[:current_turn] != user_id
      tags = state[:participants].map { |p| "@#{p}" }.join(" ")
      message = "#{tags}\n\n"
      message += "@#{user_id} 당신의 차례가 아닙니다.\n\n"
      current_name = get_user_name(state[:current_turn])
      message += "현재 턴: @#{state[:current_turn]} (#{current_name})"
      reply_to_state(state, message)
      return
    end

    # 액션 저장
    state[:actions] ||= {}
    state[:actions][user_id] = {
      type: action_type,
      target: target_id,
      potion_size: potion_size
    }

    user_name = get_user_name(user_id)

    # 턴 순서에서 다음 살아있는 플레이어 찾기
    turn_order = state[:turn_order] || state[:participants]
    current_index = turn_order.index(user_id)

    next_player = nil
    tried = 0

        while tried < turn_order.length
      next_index = (current_index + 1 + tried) % turn_order.length
      next_id = turn_order[next_index]

      # 이미 선택했거나 죽은 플레이어는 건너뛰기
      next_user = @sheet_manager.find_user(next_id)
      if !state[:actions].key?(next_id) && (next_user["HP"] || 0).to_i > 0
        next_player = next_id
        break
      end

      tried += 1
    end

    tags = state[:participants].map { |p| "@#{p}" }.join(" ")
    message = "#{tags}\n\n"
    message += "#{user_name}이(가) 행동을 선택했습니다.\n\n"

    if next_player
      # 다음 플레이어의 턴
      state[:current_turn] = next_player
      BattleState.update(battle_id, state)

      next_name = get_user_name(next_player)
      message += "@#{next_player} (#{next_name})\n"

      if state[:type] == "pvp"
        message += "[공격] [방어] [반격] [물약사용/크기]"
      else
        message += "[공격/@타겟] [방어/@아군] [반격] [물약사용/크기/@아군]"
      end

      reply_to_state(state, message)
    else
      # 모두 선택 완료 → 라운드 처리
      BattleState.update(battle_id, state)
      process_round(state, battle_id)
    end
  end

    # 라운드 처리
  def process_round(state, battle_id)
    actions = state[:actions]
    messages = []

    tags = state[:participants].map { |p| "@#{p}" }.join(" ")

    # 1. 물약 사용
    potion_actions = actions.select { |_, a| a[:type] == :use_potion }
    potion_actions.each do |user_id, action|
      result = execute_potion(user_id, action[:potion_size], action[:target], state, battle_id)
      messages << result if result
    end

    # 2. 반격 설정
    counter_actions = actions.select { |_, a| a[:type] == :counter }
    counter_actions.each do |user_id, _|
      state[:counter_stance] ||= {}
      state[:counter_stance][user_id] = true
      messages << "#{get_user_name(user_id)}이(가) 반격 태세!"
    end

    # 3. 방어 및 대리 방어
    defend_actions = actions.select { |_, a| a[:type] == :defend }
    defend_actions.each do |user_id, action|
      target_id = action[:target]

      if target_id && target_id != user_id
        state[:protect] ||= {}
        state[:protect][target_id] = user_id
        messages << "#{get_user_name(user_id)}이(가) #{get_user_name(target_id)}을(를) 대리 방어!"
      else
        state[:guarded][user_id] = true
        messages << "#{get_user_name(user_id)}이(가) 방어 태세!"
      end
    end

    # 4. 공격 + 반격
    attack_actions = actions.select { |_, a| a[:type] == :attack }
    turn_order = state[:turn_order] || state[:participants]

        turn_order.each do |user_id|
      next unless attack_actions.key?(user_id)

      action = attack_actions[user_id]
      target_id = action[:target]

      attacker = @sheet_manager.find_user(user_id)
      defender = @sheet_manager.find_user(target_id)

      next if (attacker["HP"] || 0).to_i <= 0
      next if (defender["HP"] || 0).to_i <= 0

      if state[:type] == "2v2" || state[:type] == "4v4"
        user_team = state[:teams][:team1].include?(user_id) ? :team1 : :team2
        target_team = state[:teams][:team1].include?(target_id) ? :team1 : :team2

        if user_team == target_team
          messages << "#{get_user_name(user_id)}의 공격 실패 (아군 공격 불가)"
          next
        end
      end

      actual_defender_id = target_id
      actual_defender = defender

      if state[:protect] && state[:protect][target_id]
        protector_id = state[:protect][target_id]
        protector = @sheet_manager.find_user(protector_id)

        if (protector["HP"] || 0).to_i > 0
          actual_defender_id = protector_id
          actual_defender = protector
          messages << "#{get_user_name(protector_id)}이(가) #{get_user_name(target_id)}을(를) 대신 방어!"
        end
      end

                result = execute_attack(attacker, user_id, actual_defender, actual_defender_id, state, battle_id)

      attack_msg = "#{get_user_name(user_id)}의 공격 → #{get_user_name(actual_defender_id)}\n"
      attack_msg += "공격: #{result[:atk]} + D20(#{result[:atk_roll]}) = #{result[:atk_total]}"
      attack_msg += " [치명타!]" if result[:is_crit]
      attack_msg += "\n"
      attack_msg += "방어: #{result[:def]} + D20(#{result[:def_roll]})"
      attack_msg += " + D20(#{result[:def_bonus]})" if result[:def_bonus] > 0
      attack_msg += " = #{result[:def_total]}\n"

      if result[:damage] > 0
        attack_msg += "#{result[:damage]} 피해! (HP: #{result[:old_hp]} → #{result[:new_hp]})"
      else
        attack_msg += "공격 실패!"
      end

      messages << attack_msg

             # 반격 판정 (피해자가 반격 태세였다면)
      if state[:counter_stance] && state[:counter_stance][actual_defender_id] && result[:damage] > 0
        counter_result = execute_counter(actual_defender, actual_defender_id, attacker, user_id, result[:atk_total], state, battle_id)

        counter_msg = "\n#{get_user_name(actual_defender_id)}의 반격 판정!\n"
        counter_msg += "반격: #{counter_result[:counter_atk]} + D20(#{counter_result[:counter_roll]}) = #{counter_result[:counter_total]}\n"
        counter_msg += "공격력: #{result[:atk_total]}\n"

        if counter_result[:success]
          counter_msg += "반격 성공! #{counter_result[:counter_damage]} 피해! (HP: #{counter_result[:old_hp]} → #{counter_result[:new_hp]})"
        else
          counter_msg += "반격 실패..."
        end

        messages << counter_msg

        # 반격 태세 해제
        state[:counter_stance].delete(actual_defender_id)
      end
    end
       # 라운드 결과 출력
    message = "#{tags}\n\n"
    message += "━━━━━━ 라운드 #{state[:round]} ━━━━━━\n\n"
    message += messages.join("\n\n")
    message += "\n\n" + show_all_hp(state)

    # 승패 확인
    if check_battle_end(state, battle_id, message)
      return
    end

    # 다음 라운드 준비
    state[:round] += 1
    state[:actions] = {}
    state[:guarded] = {}
    state[:counter_stance] = {}
    state[:protect] = {}

    # 첫 번째 살아있는 플레이어부터 시작
    turn_order = state[:turn_order] || state[:participants]
    next_first = turn_order.find do |p|
      user = @sheet_manager.find_user(p)
      (user["HP"] || 0).to_i > 0
    end

    state[:current_turn] = next_first
    BattleState.update(battle_id, state)

        message += "\n\n━━━━━━ 다음 라운드 ━━━━━━\n\n"

    if next_first
      next_name = get_user_name(next_first)
      message += "@#{next_first} (#{next_name})\n"

      if state[:type] == "pvp"
        message += "[공격] [방어] [반격] [물약사용/크기]"
      else
        message += "[공격/@타겟] [방어/@아군] [반격] [물약사용/크기/@아군]"
      end
    end

    reply_to_state(state, message)
  end

    # 사용자 이름 가져오기
  def get_user_name(user_id)
    user = @sheet_manager.find_user(user_id)
    user ? (user["이름"] || user_id) : user_id
  end

  # Visibility 가져오기
  def get_visibility(status)
    if status.respond_to?(:visibility)
      status.visibility
    elsif status.is_a?(Hash)
      status['visibility'] || status[:visibility] || 'public'
    else
      'public'
    end
  end

  # Status URI 가져오기
  def get_status_uri(status)
    if status.respond_to?(:uri)
      status.uri
    elsif status.respond_to?(:id)
      status.id.to_s
    elsif status.is_a?(Hash)
      status['uri'] || status[:uri] || status['id'] || status[:id]
    else
      nil
    end
  end

  # Status에 응답
  def reply_to_status(status, message, visibility = nil)
    use_visibility = visibility || get_visibility(status)
    if message.length <= 490
      @client.reply(status, message, visibility: use_visibility)
    else
      # 타래로 분할 전송
      parts = split_message(message)
      previous_status = status
      parts.each_with_index do |part, index|
        previous_status = @client.reply(previous_status, part, visibility: use_visibility)
      end
    end
  end

  # State에 응답
  def reply_to_state(state, message)
    original_status = state[:original_status]
    visibility = state[:visibility] || 'public'

    if original_status
      reply_to_status(original_status, message, visibility)
    else
      status = {
        'id' => state[:thread_ts],
        'visibility' => visibility
      }
      @client.reply(status, message, visibility: visibility)
    end
  end

  # 메시지 분할 (마스토돈용 타래)
  def split_message(message, max_length = 490)
    lines = message.split("\n")
    parts = []
    current = ""

    lines.each do |line|
      if current.length + line.length + 1 > max_length
        parts << current.strip
        current = ""
      end
      current += line + "\n"
    end

    parts << current.strip unless current.empty?
    parts
  end
end
