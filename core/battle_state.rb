class BattleState
  # battle_id => state 해시
  @@states = {}
  # user_id(string) => battle_id
  @@user_to_battle = {}

  # 특정 battle_id가 활성인지, 인자 없으면 전체 여부
  def self.active?(battle_id = nil)
    if battle_id
      !!@@states[battle_id]
    else
      !@@states.empty?
    end
  end

  # battle_id로 전투 상태 가져오기
  def self.get(battle_id)
    @@states[battle_id]
  end

  # battle_id에 전투 상태 저장
  def self.set(battle_id, state)
    @@states[battle_id] = state
  end

  # 해당 battle_id 전투만 종료
  def self.clear(battle_id)
    state = @@states.delete(battle_id)
    if state && state[:participants].respond_to?(:each)
      state[:participants].each do |pid|
        @@user_to_battle.delete(pid.to_s)
      end
    end
  end

  # 유저가 속한 battle_id 조회 (없으면 nil)
  def self.battle_of(user_id)
    @@user_to_battle[user_id.to_s]
  end

  # 유저를 battle_id에 매핑
  def self.assign_user(user_id, battle_id)
    @@user_to_battle[user_id.to_s] = battle_id
  end

  # 해당 battle_id에서 턴 넘기기(기존 next_turn 유지)
  def self.next_turn(battle_id)
    state = @@states[battle_id]
    return unless state && state[:turn_order] && state[:current_turn]

    current_index = state[:turn_order].index(state[:current_turn])
    return unless current_index

    next_index = (current_index + 1) % state[:turn_order].length
    state[:current_turn] = state[:turn_order][next_index]
  end
end
