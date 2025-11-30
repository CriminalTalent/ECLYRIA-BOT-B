class BattleState
  # 여러 전투를 동시에 관리
  @@states = {}       # { battle_id => state_hash }
  @@user_battle = {}  # { user_id => battle_id }

  # 해당 battle_id 전투 존재 여부
  def self.active?(battle_id)
    @@states.key?(battle_id)
  end

  # 해당 battle_id 전투 상태 조회
  def self.get(battle_id)
    @@states[battle_id]
  end

  # 전투 상태 저장
  def self.set(battle_id, state)
    @@states[battle_id] = state
  end

  # 전투 종료
  def self.clear(battle_id)
    return unless @@states[battle_id]
    
    # 해당 전투에 소속된 모든 유저 해제
    participants = @@states[battle_id][:participants] || []
    participants.each { |pid| @@user_battle.delete(pid) }

    @@states.delete(battle_id)
  end

  # 유저 소속 전투 조회
  def self.battle_of(user_id)
    @@user_battle[user_id]
  end

  # 유저를 battle_id 에 소속
  def self.assign_user(user_id, battle_id)
    @@user_battle[user_id] = battle_id
  end

  # 다음 턴 처리
  def self.next_turn(battle_id)
    state = @@states[battle_id]
    return unless state

    current_index = state[:turn_order].index(state[:current_turn])
    next_index = (current_index + 1) % state[:turn_order].length
    state[:current_turn] = state[:turn_order][next_index]
  end
end
