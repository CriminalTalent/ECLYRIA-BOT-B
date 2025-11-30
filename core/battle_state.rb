# core/battle_engine.rb
# encoding: UTF-8

require_relative 'battle_state'

class BattleEngine
  def initialize(sheet_manager, mastodon)
    @sheet_manager = sheet_manager
    @mastodon = mastodon
    @states = {}  # battle_id => BattleState
  end

  # 전투 시작
  def start_battle(attacker_id, defender_id)
    return if in_battle?(attacker_id) || in_battle?(defender_id)

    battle_id = "#{attacker_id}_vs_#{defender_id}_#{Time.now.to_i}"

    @states[battle_id] = BattleState.new(attacker_id, defender_id)

    save_battle_state(battle_id)
    battle_id
  end

  # 전투 중인지 검사
  def in_battle?(player_id)
    @states.values.any? { |s| s.active? && s.include?(player_id) }
  end

  # 플레이어가 포함된 전투 ID 반환
  def find_battle(player_id)
    @states.each do |id, state|
      return id if state.active? && state.include?(player_id)
    end
    nil
  end

  # 공격 처리 (물리 or 마법)
  def attack(battle_id, attacker_id, attack_type)
    state = @states[battle_id]
    return error("전투 상태를 찾을 수 없습니다.") unless state

    unless state.turn_player == attacker_id
      return error("지금은 #{state.turn_player}의 차례입니다.")
    end

    damage = roll_damage(attack_type)
    state.apply_damage(attacker_id, damage)

    save_battle_state(battle_id)

    result = {
      damage: damage,
      target: state.opponent_of(attacker_id),
      hp: state.hp[state.opponent_of(attacker_id)]
    }

    if state.finished?
      result[:finished] = true
      result[:winner] = state.winner
    else
      state.next_turn
    end

    result
  end

  # 방어 처리
  def defend(battle_id, defender_id)
    state = @states[battle_id]
    return error("전투 상태 없음") unless state
    return error("당신의 차례가 아닙니다!") unless state.turn_player == defender_id

    block = rand(5..15)
    state.heal(defender_id, block)

    save_battle_state(battle_id)

    state.next_turn

    { block: block }
  end

  # 도망 처리
  def flee(battle_id, player_id)
    state = @states[battle_id]
    return error("전투 상태 없음") unless state

    success = rand < 0.5
    if success
      state.terminate(player_id)
      save_battle_state(battle_id)
      return { fled: true }
    end

    save_battle_state(battle_id)
    { fled: false }
  end

  # ===== 내부 유틸 =====

  def roll_damage(type)
    case type
    when :physical then rand(8..18)
    when :magic then rand(10..22)
    else rand(5..10)
    end
  end

  # 시트 저장(매 턴 후)
  def save_battle_state(battle_id)
    state = @states[battle_id]
    return unless state

    @sheet_manager.update_battle_log(
      battle_id,
      state.attacker, state.defender,
      state.hp[state.attacker], state.hp[state.defender],
      state.turn_player
    )
  end

  # 종료/완료 전투 정리
  def cleanup_finished
    @states.delete_if { |_, s| !s.active? }
  end

  def error(msg)
    { error: msg }
  end
end
