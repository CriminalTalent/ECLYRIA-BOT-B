class BattleState
  @battles = {}
  @mutex = Mutex.new
  
  GM_ACCOUNTS = ['Story', 'professor', 'Store', 'FortunaeFons'].freeze

  def self.create(participants, state_data)
    @mutex.synchronize do
      battle_id = generate_battle_id(participants)
      @battles[battle_id] = state_data.merge(
        battle_id: battle_id,
        start_time: Time.now,
        last_action_time: Time.now
      )
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
        @battles[battle_id][:last_action_time] = Time.now if updates.keys.any? { |k| [:current_turn, :actions_queue].include?(k) }
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

  def self.all_battles
    @mutex.synchronize do
      @battles.dup
    end
  end

  def self.count
    @mutex.synchronize do
      @battles.size
    end
  end

  # 시간 초과 체크
  def self.check_timeouts
    @mutex.synchronize do
      @battles.each do |battle_id, state|
        turn_elapsed = Time.now - state[:last_action_time]
        battle_elapsed = Time.now - state[:start_time]
        
        # 턴 시간 초과 (4분)
        if turn_elapsed > 240
          state[:timeout_turn] = true
        end
        
        # 전투 시간 초과 (1시간)
        if battle_elapsed > 3600
          state[:timeout_battle] = true
        end
      end
    end
  end

  # 멈춘 전투 정리 (2시간 이상 액션 없음)
  def self.cleanup_stalled_battles
    @mutex.synchronize do
      now = Time.now
      @battles.delete_if do |battle_id, state|
        (now - state[:last_action_time]) > 7200
      end
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
