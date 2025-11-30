# core/battle_state.rb
class BattleState
  @@state = nil
  @@active_players = []

  # 운영 이벤트 계정(다중 전투 허용)
  WHITELIST = ["Story", "professor"].freeze

  def self.active?
    !@@state.nil?
  end

  def self.get
    @@state
  end

  def self.set(state)
    @@state = state
    register_players(state)
  end

  # 플레이어 등록 — 운영 계정 제외
  def self.register_players(state)
    return if state.nil?

    (state[:players] || []).each do |p|
      next if WHITELIST.include?(p)
      @@active_players << p unless @@active_players.include?(p)
    end
  end

  def self.clear
    unregister_players
    @@state = nil
  end

  # 플레이어 전투 종료 기록 제거
  def self.unregister_players
    return if @@state.nil?
    (@@state[:players] || []).each do |p|
      next if WHITELIST.include?(p)
      @@active_players.delete(p)
    end
  end

  def self.player_in_battle?(player)
    return false if WHITELIST.include?(player)
    @@active_players.include?(player)
  end

  def self.next_turn
    return unless @@state

    order = @@state[:turn_order]
    current = @@state[:current_turn]
    i = order.index(current) || 0
    next_i = (i + 1) % order.length
    @@state[:current_turn] = order[next_i]
  end
end
