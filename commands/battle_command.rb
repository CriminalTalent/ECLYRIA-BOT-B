# commands/battle_command.rb

require_relative '../core/battle_engine'
require_relative '../core/battle_state'

class BattleCommand
  def initialize(client, sheet_manager)
    @client = client
    @sheet_manager = sheet_manager
    @engine = BattleEngine.new(@client, @sheet_manager)
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
    
    # 전투 시작
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
    
    @engine.start_4v4_battle(team1, team2, reply_status)
  end

  # 공격 (액션 등록)
  def attack(user_id, target_id, reply_status)
    battle = BattleState.find_by_participant(user_id)
    
    unless battle
      @client.reply(reply_status, "@#{user_id} 전투 중이 아닙니다.")
      return
    end
    
    battle_id = battle[:battle_id]
    state = BattleState.get(battle_id)
    
    # 이미 행동을 선택했는지 확인
    if state[:actions] && state[:actions].key?(user_id)
      @client.reply(reply_status, "@#{user_id} 이미 행동을 선택했습니다.")
      return
    end
    
    # 전투 타입에 따라 처리
    case state[:type]
    when "pvp"
      # 1:1은 상대가 자동으로 타겟
      opponent_id = state[:participants].find { |p| p != user_id }
      @engine.register_action(user_id, :attack, opponent_id, battle_id)
      
    when "2v2", "4v4"
      unless target_id
        @client.reply(reply_status, "@#{user_id} 팀 전투에서는 [공격/@타겟]으로 대상을 지정해야 합니다.")
        return
      end
      @engine.register_action(user_id, :attack, target_id, battle_id)
    end
  end

  # 방어 (액션 등록)
  def defend(user_id, target_id, reply_status)
    battle = BattleState.find_by_participant(user_id)
    
    unless battle
      @client.reply(reply_status, "@#{user_id} 전투 중이 아닙니다.")
      return
    end
    
    battle_id = battle[:battle_id]
    state = BattleState.get(battle_id)
    
    # 이미 행동을 선택했는지 확인
    if state[:actions] && state[:actions].key?(user_id)
      @client.reply(reply_status, "@#{user_id} 이미 행동을 선택했습니다.")
      return
    end
    
    # target_id가 없으면 자신을 방어
    defend_target = target_id || user_id
    
    # 팀전에서 아군인지 확인
    if state[:type] == "2v2" || state[:type] == "4v4"
      if target_id
        user_team = state[:teams][:team1].include?(user_id) ? :team1 : :team2
        target_team = state[:teams][:team1].include?(target_id) ? :team1 : :team2
        
        if user_team != target_team
          @client.reply(reply_status, "@#{user_id} 아군만 방어할 수 있습니다.")
          return
        end
      end
    end
    
    @engine.register_action(user_id, :defend, defend_target, battle_id)
  end

  # 반격 (액션 등록)
  def counter(user_id, reply_status)
    battle = BattleState.find_by_participant(user_id)
    
    unless battle
      @client.reply(reply_status, "@#{user_id} 전투 중이 아닙니다.")
      return
    end
    
    battle_id = battle[:battle_id]
    state = BattleState.get(battle_id)
    
    # 이미 행동을 선택했는지 확인
    if state[:actions] && state[:actions].key?(user_id)
      @client.reply(reply_status, "@#{user_id} 이미 행동을 선택했습니다.")
      return
    end
    
    @engine.register_action(user_id, :counter, nil, battle_id)
  end

  # 물약 사용 (액션 등록)
  def use_potion(user_id, potion_size, target_id, reply_status)
    battle = BattleState.find_by_participant(user_id)
    
    unless battle
      @client.reply(reply_status, "@#{user_id} 전투 중이 아닙니다.")
      return
    end
    
    battle_id = battle[:battle_id]
    state = BattleState.get(battle_id)
    
    # 이미 행동을 선택했는지 확인
    if state[:actions] && state[:actions].key?(user_id)
      @client.reply(reply_status, "@#{user_id} 이미 행동을 선택했습니다.")
      return
    end
    
    # target_id가 없으면 자신에게 사용
    heal_target = target_id || user_id
    
    # 팀전에서 아군인지 확인
    if state[:type] == "2v2" || state[:type] == "4v4"
      if target_id
        user_team = state[:teams][:team1].include?(user_id) ? :team1 : :team2
        target_team = state[:teams][:team1].include?(target_id) ? :team1 : :team2
        
        if user_team != target_team
          @client.reply(reply_status, "@#{user_id} 아군에게만 물약을 사용할 수 있습니다.")
          return
        end
      end
    end
    
    @engine.register_action(user_id, :use_potion, heal_target, battle_id, potion_size)
  end
end
