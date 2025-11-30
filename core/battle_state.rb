# battle_state.rb (멀티 전투 지원 안정 버전)
# =============================================
class BattleState
  # 여러 전투 동시 관리
  # 예: { "snow_white_vs_bridget" => { ...battle data... } }
  @@states = {}

  # 플레이어가 참여한 전투 ID 찾기
  # 한 사람은 하나의 전투만 참여 가능
  def self.find_by_player(player_id)
    @@states.each do |battle_id, state|
      return battle_id if state[:players].include?(player_id)
    end
    nil
  end

  # 전투 생성 / 설정
  def self.set(battle_id, state)
    @@states[battle_id] = state
  end

  # 특정 전투 조회
  def self.get(battle_id)
    @@states[battle_id]
  end

  # 특정 전투 제거
  def self.clear(battle_id)
    @@states.delete(battle_id)
  end

  # 현재 활성화된 모든 전투 목록
  def self.active_battles
    @@states.keys
  end

  # 플레이어가 이미 전투 중인지 확인
  def self.player_in_battle?(player_id)
    !find_by_player(player_id).nil?
  end

  # 현재 턴 진행(개별 전투만 대상)
  def self.next_turn(battle_id)
    return unless @@states[battle_id]

    state = @@states[battle_id]
    current = state[:current_turn]
    idx = state[:turn_order].index(current)
    next_idx = (idx + 1) % state[:turn_order].length
    state[:current_turn] = state[:turn_order][next_idx]
  end
end
