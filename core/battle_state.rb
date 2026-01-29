class BattleState
  @battles = {}
  @mutex = Mutex.new
  
  GM_ACCOUNTS = ['Story', 'professor', 'Store', 'FortunaeFons'].freeze

  def self.create(participants, state_data)
    @mutex.synchronize do
      battle_id = generate_battle_id(participants)
      @battles[battle_id] = state_data.merge(battle_id: battle_id)
      battle_id
    end
  end

  def self.get(battle_id)
    @mutex.synchronize do
      @battles[battle_id]
    end
  end

  def self.find_by_user(user_id)
    return nil if GM_ACCOUNTS.include?(user_id)
    
    @mutex.synchronize do
      @battles.values.find { |state| state[:participants].include?(user_id) }
    end
  end

  def self.find_battle_id_by_user(user_id)
    return nil if GM_ACCOUNTS.include?(user_id)
    
    @mutex.synchronize do
      battle = @battles.find { |id, state| state[:participants].include?(user_id) }
      battle ? battle[0] : nil
    end
  end

  def self.find_battle_by_participants(participant_list)
    @mutex.synchronize do
      @battles.find do |id, state|
        participant_list.all? { |p| state[:participants].include?(p) }
      end&.first
    end
  end

  def self.player_in_battle?(user_id)
    return false if GM_ACCOUNTS.include?(user_id)
    
    @mutex.synchronize do
      @battles.values.any? { |state| state[:participants].include?(user_id) }
    end
  end

  def self.update(battle_id, updates)
    @mutex.synchronize do
      if @battles[battle_id]
        @battles[battle_id].merge!(updates)
      end
    end
  end

  def self.clear(battle_id)
    @mutex.synchronize do
      @battles.delete(battle_id)
    end
  end

  def self.clear_all
    @mutex.synchronize do
      @battles.clear
    end
  end

  def self.all
    @mutex.synchronize do
      @battles.dup
    end
  end

  def self.count
    @mutex.synchronize do
      @battles.size
    end
  end

  private

  def self.generate_battle_id(participants)
    sorted = participants.sort.join('_')
    timestamp = Time.now.to_i
    random = rand(10000)
    "battle_#{sorted}_#{timestamp}_#{random}"
  end
end
