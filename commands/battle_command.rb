# commands/battle_command.rb
# Mastodon 기반 전투 명령어 처리 (1:1, 2:2, 4:4)

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
    
    # 전투 시작 (중복 체크 제거 - 동시 전투 가능)
    @engine.start_battle(user_id, opponent_id, reply_status)
  end

  # 2:2 전투 시작
  def start_2v2(p1, p2, p3, p4, reply_status)
    participants = [p1, p2, p3, p4]
    
    # 같은 전투 내 중복만 확인
    if participants.uniq.length != 4
      @client.reply(reply_status, "참가자가 중복되었습니다!")
      return
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
    
    # 동시 전투 가능
    @engine.start_2v2_battle(team1, team2, reply_status)
  end

  # 4:4 전투 시작
  def start_4v4(p1, p2, p3, p4, p5, p6, p7, p8, reply_status)
    participants = [p1, p2, p3, p4, p5, p6, p7, p8]
    
    # 같은 전투 내 중복만 확인
    if participants.uniq.length != 8
      @client.reply(reply_status, "참가자가 중복되었습니다!")
      return
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
    
    # 동시 전투 가능
    @engine.start_4v4_battle(team1, team2, reply_status)
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
    when "pvp"
      @engine.handle_battle_action(user_id, :attack, battle_id)
    when "2v2", "4v4"
      unless target_id
        @client.reply(reply_status, "@#{user_id} 팀 전투에서는 [공격/@타겟]으로 대상을 지정해야 합니다.")
        return
      end
      @engine.handle_multi_action(user_id, :attack, target_id, battle_id, state)
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
    when "pvp"
      # 자신 방어
      @engine.handle_battle_action(user_id, :defend, battle_id)
    when "2v2", "4v4"
      if target_id
        # 아군 방어
        @engine.handle_multi_action(user_id, :defend_target, target_id, battle_id, state)
      else
        # 자신 방어
        @engine.handle_multi_action(user_id, :defend, nil, battle_id, state)
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
    when "pvp"
      @engine.handle_battle_action(user_id, :counter, battle_id)
    when "2v2", "4v4"
      @engine.handle_multi_action(user_id, :counter, nil, battle_id, state)
    end
  end
end
