class BattleState
  @@state = nil

  def self.active?
    !@@state.nil?
  end

  def self.get
    @@state
  end

  def self.set(state)
    @@state = state
  end

  def self.clear
    @@state = nil
  end

  def self.next_turn
    return unless @@state
    
    current_index = @@state[:turn_order].index(@@state[:current_turn])
    next_index = (current_index + 1) % @@state[:turn_order].length
    @@state[:current_turn] = @@state[:turn_order][next_index]
  end
end
