class BattleState
  @battles = {}
  @mutex = Mutex.new

  # 새 전투 생성
  def self.create(participants, state_data)
    @mutex.synchronize do
      battle_id = generate_battle_id(participants)
      @battles[battle_id] = state_data.merge(battle_id: battle_id)
      battle_id
    end
  end

  # 전투 ID로 조회
  def self.get(battle_id)
    @mutex.synchronize do
      @battles[battle_id]
    end
  end

  # 사용자가 참여 중인 전투 찾기
  def self.find_by_user(user_id)
    @mutex.synchronize do
      @battles.values.find { |state| state[:participants].include?(user_id) }
    end
  end

  # 사용자의 전투 ID 찾기
  def self.find_battle_id_by_user(user_id)
    @mutex.synchronize do
      battle = @battles.find { |id, state| state[:participants].include?(user_id) }
      battle ? battle[0] : nil
    end
  end

  # 사용자가 전투 중인지 확인
  def self.player_in_battle?(user_id)
    @mutex.synchronize do
      @battles.values.any? { |state| state[:participants].include?(user_id) }
    end
  end

  # 전투 상태 업데이트
  def self.update(battle_id, updates)
    @mutex.synchronize do
      if @battles[battle_id]
        @battles[battle_id].merge!(updates)
      end
    end
  end

  # 전투 종료 (삭제)
  def self.clear(battle_id)
    @mutex.synchronize do
      @battles.delete(battle_id)
    end
  end

  # 모든 전투 종료
  def self.clear_all
    @mutex.synchronize do
      @battles.clear
    end
  end

  # 전투 목록
  def self.all
    @mutex.synchronize do
      @battles.dup
    end
  end

  # 전투 개수
  def self.count
    @mutex.synchronize do
      @battles.size
    end
  end

  private

  # 전투 ID 생성
  def self.generate_battle_id(participants)
    sorted = participants.sort.join('_')
    timestamp = Time.now.to_i
    "battle_#{sorted}_#{timestamp}"
  end
end
