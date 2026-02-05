# state/battle_state.rb

class BattleState
  @battles = {}
  @mutex = Mutex.new
  
  class << self
    # 새 전투 생성
    def create(battle_id, initial_state = {})
      @mutex.synchronize do
        @battles[battle_id] = {
          battle_id: battle_id,
          created_at: Time.now,
          last_action_time: Time.now
        }.merge(initial_state)
        battle_id
      end
    end
    
    # 전투 상태 조회
    def get(battle_id)
      @mutex.synchronize { @battles[battle_id]&.dup }
    end
    
    # 스레드로 전투 찾기
    def find_by_thread(thread_ts)
      @mutex.synchronize do
        @battles.values.find { |b| b[:thread_ts] == thread_ts }
      end
    end
    
    # 참가자로 전투 찾기
    def find_by_participant(user_id)
      @mutex.synchronize do
        @battles.values.find { |b| b[:participants]&.include?(user_id) }
      end
    end
    
    # 참가자들로 전투 ID 찾기
    def find_battle_by_participants(participant_list)
      @mutex.synchronize do
        @battles.each do |battle_id, battle|
          # 참가자 목록이 일치하는지 확인
          if battle[:participants] && participant_list.all? { |p| battle[:participants].include?(p) }
            return battle_id
          end
        end
        nil
      end
    end
    
    # 전투 ID로 battle_id 조회
    def find_battle_id_by_thread(thread_ts)
      battle = find_by_thread(thread_ts)
      battle ? battle[:battle_id] : nil
    end
    
    # 전투 상태 업데이트 (없으면 자동 생성)
    def update(battle_id, updates)
      @mutex.synchronize do
        # 전투가 없으면 새로 생성
        unless @battles[battle_id]
          @battles[battle_id] = {
            battle_id: battle_id,
            created_at: Time.now,
            last_action_time: Time.now
          }
        end
        
        @battles[battle_id].merge!(updates)
        @battles[battle_id][:last_action_time] = Time.now
        true
      end
    end
    
    # 전투 삭제
    def delete(battle_id)
      @mutex.synchronize { @battles.delete(battle_id) }
    end
    
    # 전투 완전 제거 (clear와 동일)
    def clear(battle_id)
      delete(battle_id)
    end
    
    # 모든 전투 조회
    def all_battles
      @mutex.synchronize { @battles.dup }
    end
    
    # 오래된 전투 정리 (1시간 기본)
    def cleanup_old_battles(timeout_seconds = 3600)
      @mutex.synchronize do
        now = Time.now
        deleted_count = 0
        @battles.delete_if do |_id, battle|
          is_old = (now - battle[:last_action_time]) > timeout_seconds
          deleted_count += 1 if is_old
          is_old
        end
        deleted_count
      end
    end
    
    # 전투 존재 확인
    def exists?(battle_id)
      @mutex.synchronize { @battles.key?(battle_id) }
    end
    
    # 활성 전투 수
    def active_count
      @mutex.synchronize { @battles.size }
    end
    
    # 디버그용 - 모든 전투 ID 목록
    def all_battle_ids
      @mutex.synchronize { @battles.keys }
    end
  end
end
