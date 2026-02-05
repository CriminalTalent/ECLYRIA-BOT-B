# commands/battle_command.rb
# Mastodon 기반 전투 명령어 처리

require_relative '../core/battle_engine'
require_relative '../state/battle_state'

class BattleCommand
  def initialize(mastodon_client, sheet_manager)
    @client = mastodon_client
    @sheet_manager = sheet_manager
    @engine = BattleEngine.new(mastodon_client)
  end

  # 1:1 전투 시작
  def start_1v1(user_id, opponent_id, reply_status)
    # 이미 전투 중인지 확인
    if BattleState.find_by_participant(user_id)
      @client.reply(reply_status, "@#{user_id} 이미 전투 중입니다!")
      return
    end
    
    if BattleState.find_by_participant(opponent_id)
      @client.reply(reply_status, "@#{opponent_id}는 이미 전투 중입니다!")
      return
    end
    
    # 참가자 확인
    user = @sheet_manager.find_user(user_id)
    opponent = @sheet_manager.find_user(opponent_id)
    
    unless user
      @client.reply(reply_status, "@#{user_id} 사용자를 찾을 수 없습니다.")
      return
    end
    
    unless opponent
      @client.reply(reply_status, "@#{opponent_id} 사용자를 찾을 수 없습니다.")
      return
    end
    
    # 전투 시작
    @engine.start_battle(user_id, opponent_id, reply_status)
  end

  # 2:2 전투 시작
  def start_2v2(p1, p2, p3, p4, reply_status)
    participants = [p1, p2, p3, p4]
    
    # 중복 확인
    if participants.uniq.length != 4
      @client.reply(reply_status, "참가자가 중복되었습니다!")
      return
    end
    
    # 이미 전투 중인지 확인
    participants.each do |pid|
      if BattleState.find_by_participant(pid)
        @client.reply(reply_status, "@#{pid}는 이미 전투 중입니다!")
        return
      end
    end
    
    # 모든 참가자 확인
    participants.each do |pid|
      unless @sheet_manager.find_user(pid)
        @client.reply(reply_status, "@#{pid} 사용자를 찾을 수 없습니다.")
        return
      end
    end
    
    # 팀 분할 (1-2 vs 3-4)
    team1 = [p1, p2]
    team2 = [p3, p4]
    
    @engine.start_2v2_battle(team1, team2, reply_status)
  end

  # 4:4 전투 시작
  def start_4v4(p1, p2, p3, p4, p5, p6, p7, p8, reply_status)
    participants = [p1, p2, p3, p4, p5, p6, p7, p8]
    
    # 중복 확인
    if participants.uniq.length != 8
      @client.reply(reply_status, "참가자가 중복되었습니다!")
      return
    end
    
    # 이미 전투 중인지 확인
    participants.each do |pid|
      if BattleState.find_by_participant(pid)
        @client.reply(reply_status, "@#{pid}는 이미 전투 중입니다!")
        return
      end
    end
    
    # 모든 참가자 확인
    participants.each do |pid|
      unless @sheet_manager.find_user(pid)
        @client.reply(reply_status, "@#{pid} 사용자를 찾을 수 없습니다.")
        return
      end
    end
    
    # 팀 분할 (1-4 vs 5-8)
    team1 = [p1, p2, p3, p4]
    team2 = [p5, p6, p7, p8]
    
    # 4v4는 2v2 확장 버전으로 구현
    # TODO: 별도 4v4 로직이 필요하면 추가
    @client.reply(reply_status, "4:4 전투는 아직 구현 중입니다. 2:2 전투를 이용해주세요.")
  end

  # 공격
  def attack(user_id, target_id, reply_status)
    battle = BattleState.find_by_participant(user_id)
    
    unless battle
      @client.reply(reply_status, "@#{user_id} 전투 중이 아닙니다.")
      return
    end
    
    battle_id = battle[:battle_id]
    state = BattleState.get(battle_id)
    
    # 턴 확인
    unless state[:current_turn] == user_id
      @client.reply(reply_status, "@#{user_id} 당신의 차례가 아닙니다.")
      return
    end
    
    # 전투 타입에 따라 처리
    case state[:type]
    when "pvp", "dummy"
      @engine.handle_battle_action(user_id, :attack, battle_id)
    when "2v2"
      unless target_id
        @client.reply(reply_status, "@#{user_id} 2:2 전투에서는 [공격/@타겟]으로 대상을 지정해야 합니다.")
        return
      end
      @engine.handle_2v2_action(user_id, :attack, target_id, battle_id, state)
    end
  end

  # 방어
  def defend(user_id, target_id, reply_status)
    battle = BattleState.find_by_participant(user_id)
    
    unless battle
      @client.reply(reply_status, "@#{user_id} 전투 중이 아닙니다.")
      return
    end
    
    battle_id = battle[:battle_id]
    state = BattleState.get(battle_id)
    
    # 턴 확인
    unless state[:current_turn] == user_id
      @client.reply(reply_status, "@#{user_id} 당신의 차례가 아닙니다.")
      return
    end
    
    # 전투 타입에 따라 처리
    case state[:type]
    when "pvp", "dummy"
      # 자신 방어
      @engine.handle_battle_action(user_id, :defend, battle_id)
    when "2v2"
      if target_id
        # 아군 방어
        @engine.handle_2v2_action(user_id, :defend_target, target_id, battle_id, state)
      else
        # 자신 방어
        @engine.handle_2v2_action(user_id, :defend, nil, battle_id, state)
      end
    end
  end

  # 반격
  def counter(user_id, reply_status)
    battle = BattleState.find_by_participant(user_id)
    
    unless battle
      @client.reply(reply_status, "@#{user_id} 전투 중이 아닙니다.")
      return
    end
    
    battle_id = battle[:battle_id]
    state = BattleState.get(battle_id)
    
    # 턴 확인
    unless state[:current_turn] == user_id
      @client.reply(reply_status, "@#{user_id} 당신의 차례가 아닙니다.")
      return
    end
    
    # 전투 타입에 따라 처리
    case state[:type]
    when "pvp", "dummy"
      @engine.handle_battle_action(user_id, :counter, battle_id)
    when "2v2"
      @engine.handle_2v2_action(user_id, :counter, nil, battle_id, state)
    end
  end

  # 도주
  def flee(user_id, reply_status)
    battle = BattleState.find_by_participant(user_id)
    
    unless battle
      @client.reply(reply_status, "@#{user_id} 전투 중이 아닙니다.")
      return
    end
    
    battle_id = battle[:battle_id]
    state = BattleState.get(battle_id)
    
    # 턴 확인
    unless state[:current_turn] == user_id
      @client.reply(reply_status, "@#{user_id} 당신의 차례가 아닙니다.")
      return
    end
    
    user = @sheet_manager.find_user(user_id)
    user_name = user["이름"] || user_id
    
    # 도주 성공률 계산 (민첩성 기반)
    agility = (user["민첩성"] || 10).to_i
    flee_chance = [30 + agility, 90].min  # 최소 30%, 최대 90%
    roll = rand(1..100)
    
    if roll <= flee_chance
      # 도주 성공
      message = "#{user_name}이(가) 전투에서 도주했습니다! (성공률: #{flee_chance}%, 주사위: #{roll})"
      
      # 전투 종료
      if state[:reply_status]
        @client.reply(state[:reply_status], message)
      else
        @client.reply(reply_status, message)
      end
      
      BattleState.clear(battle_id)
    else
      # 도주 실패
      message = "#{user_name}의 도주 실패! (성공률: #{flee_chance}%, 주사위: #{roll})\n"
      message += "턴이 넘어갑니다."
      
      # 턴 넘기기
      case state[:type]
      when "pvp"
        opponent_id = state[:participants].find { |p| p != user_id }
        opponent = @sheet_manager.find_user(opponent_id)
        opponent_name = opponent["이름"] || opponent_id
        
        state[:current_turn] = opponent_id
        state[:round] += 1
        BattleState.update(battle_id, state)
        
        message += "\n\n#{opponent_name}의 차례\n"
        message += "[공격] [방어] [반격] [물약] [도주]"
        
      when "2v2"
        state[:turn_index] += 1
        if state[:turn_index] >= 4
          # 라운드 종료, 액션 큐에 도주 실패 추가
          state[:actions_queue] << { user_id: user_id, action: :flee_failed }
          BattleState.update(battle_id, state)
          @engine.process_2v2_round(battle_id, state, message + "\n")
          return
        else
          state[:current_turn] = state[:turn_order][state[:turn_index]]
          BattleState.update(battle_id, state)
          
          next_player = @sheet_manager.find_user(state[:current_turn])
          next_player_name = next_player["이름"] || state[:current_turn]
          
          message += "\n\n#{next_player_name}의 차례\n"
          message += "[공격/@타겟] [방어] [방어/@아군] [반격] [물약] [도주]"
        end
      end
      
      if state[:reply_status]
        @client.reply(state[:reply_status], message)
      else
        @client.reply(reply_status, message)
      end
    end
  end
end
