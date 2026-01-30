class BattleState
  @battles = {}
  @mutex = Mutex.new
  
  class << self
    def create(thread_id, participants, options = {})
      @mutex.synchronize do
        battle_id = "battle_#{thread_id}_#{Time.now.to_i}"
        @battles[battle_id] = {
          thread_id: thread_id,
          battle_id: battle_id,
          participants: participants,
          team_a: options[:team_a] || [],
          team_b: options[:team_b] || [],
          turn_order: options[:turn_order] || [],
          current_turn: options[:current_turn],
          guarded: {},
          counter: {},
          hp_data: {},
          created_at: Time.now,
          last_action_time: Time.now,
          reply_status: options[:reply_status],
          gm_user: options[:gm_user]
        }
        participants.each do |user_id|
          @battles[battle_id][:hp_data][user_id] = options[:hp_data]&.dig(user_id) || 100
        end
        battle_id
      end
    end
    
    def get(battle_id)
      @mutex.synchronize { @battles[battle_id] }
    end
    
    def find_by_thread(thread_id)
      @mutex.synchronize do
        @battles.values.find { |b| b[:thread_id] == thread_id }
      end
    end
    
    def find_by_participant(user_id)
      @mutex.synchronize do
        @battles.values.find { |b| b[:participants].include?(user_id) }
      end
    end
    
    def find_battle_id_by_thread(thread_id)
      battle = find_by_thread(thread_id)
      battle ? battle[:battle_id] : nil
    end
    
    def update(battle_id, updates)
      @mutex.synchronize do
        return false unless @battles[battle_id]
        @battles[battle_id].merge!(updates)
        @battles[battle_id][:last_action_time] = Time.now
        true
      end
    end
    
    def delete(battle_id)
      @mutex.synchronize { @battles.delete(battle_id) }
    end
    
    def all_battles
      @mutex.synchronize { @battles.dup }
    end
    
    def cleanup_old_battles(timeout_seconds = 3600)
      @mutex.synchronize do
        now = Time.now
        @battles.delete_if do |_id, battle|
          (now - battle[:last_action_time]) > timeout_seconds
        end
      end
    end
  end
end
