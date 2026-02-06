# core/battle_state.rb
# 개선된 전투 상태 관리 - 시간 제한 지원

class BattleState
  @@battles = {}
  @@battle_counter = 0

  class << self
    def create(participants, state_data)
      @@battle_counter += 1
      battle_id = "battle_#{@@battle_counter}_#{Time.now.to_i}"
      
      # 기본 시간 정보 추가
      state_data[:battle_start_time] ||= Time.now
      state_data[:last_action_time] ||= Time.now
      
      @@battles[battle_id] = state_data
      
      # 참가자별 인덱스 생성 (빠른 검색을 위해)
      participants.each do |participant_id|
        @@battles["user_#{participant_id}"] = battle_id
      end
      
      puts "[전투 상태] 생성: #{battle_id} (참가자: #{participants.join(', ')})"
      battle_id
    end

    def get(battle_id = nil)
      return @@battles if battle_id.nil?
      @@battles[battle_id]
    end

    def get_all_battles
      # 실제 전투 ID만 반환 (user_ 접두사가 없는 것들)
      @@battles.select { |k, v| !k.start_with?("user_") && v.is_a?(Hash) }
    end

    def update(battle_id, state_data)
      return false unless @@battles[battle_id]
      
      # 마지막 액션 시간 업데이트
      state_data[:last_action_time] = Time.now
      
      @@battles[battle_id] = state_data
      true
    end

    def clear(battle_id)
      state = @@battles[battle_id]
      return false unless state
      
      # 참가자별 인덱스 삭제
      if state[:participants]
        state[:participants].each do |participant_id|
          @@battles.delete("user_#{participant_id}")
        end
      end
      
      @@battles.delete(battle_id)
      puts "[전투 상태] 삭제: #{battle_id}"
      true
    end

    def find_by_user(user_id)
      battle_id = @@battles["user_#{user_id}"]
      return nil unless battle_id
      @@battles[battle_id]
    end

    def find_battle_id_by_user(user_id)
      @@battles["user_#{user_id}"]
    end

    def cleanup_expired_battles(max_age_seconds = 7200) # 2시간
      current_time = Time.now
      expired_battles = []
      
      get_all_battles.each do |battle_id, state|
        next unless state[:battle_start_time]
        
        age = current_time - state[:battle_start_time]
        if age > max_age_seconds
          expired_battles << battle_id
        end
      end
      
      expired_battles.each do |battle_id|
        puts "[전투 상태] 만료된 전투 삭제: #{battle_id}"
        clear(battle_id)
      end
      
      expired_battles.size
    end

    def get_battle_stats
      all_battles = get_all_battles
      current_time = Time.now
      
      stats = {
        total: all_battles.size,
        types: Hash.new(0),
        avg_duration: 0,
        oldest: nil,
        newest: nil
      }
      
      return stats if all_battles.empty?
      
      durations = []
      battle_times = []
      
      all_battles.each do |battle_id, state|
        # 전투 타입별 통계
        stats[:types][state[:type] || 'unknown'] += 1
        
        # 시간 통계
        if state[:battle_start_time]
          duration = current_time - state[:battle_start_time]
          durations << duration
          battle_times << state[:battle_start_time]
        end
      end
      
      if durations.any?
        stats[:avg_duration] = durations.sum / durations.size
        stats[:oldest] = battle_times.min
        stats[:newest] = battle_times.max
      end
      
      stats
    end

    def list_active_battles
      all_battles = get_all_battles
      return "진행 중인 전투가 없습니다." if all_battles.empty?
      
      result = "━━━━━━━━━━━━━━━━━━\n"
      result += "진행 중인 전투 목록\n"
      result += "━━━━━━━━━━━━━━━━━━\n"
      
      all_battles.each_with_index do |(battle_id, state), index|
        participants = state[:participants] || []
        type = state[:type] || 'unknown'
        
        duration = state[:battle_start_time] ? 
                   Time.now - state[:battle_start_time] : 0
        
        result += "#{index + 1}. [#{type.upcase}] "
        result += participants.reject { |p| p.include?("허수아비") }.join(" vs ")
        result += " (#{format_duration(duration)})\n"
        
        if state[:current_turn]
          current_name = state[:current_turn].include?("허수아비") ? 
                        "허수아비" : state[:current_turn]
          result += "   현재 턴: #{current_name}\n"
        end
      end
      
      result += "━━━━━━━━━━━━━━━━━━"
      result
    end

    def force_timeout_battle(battle_id)
      state = get(battle_id)
      return false unless state
      
      # 강제로 시간 초과 상태로 만듦
      state[:last_action_time] = Time.now - 300 # 5분 전으로 설정
      update(battle_id, state)
      true
    end

    # 위험한 전투 감지 (너무 오래 지속된 전투)
    def detect_stuck_battles(threshold_minutes = 30)
      current_time = Time.now
      stuck_battles = []
      
      get_all_battles.each do |battle_id, state|
        next unless state[:last_action_time]
        
        inactive_time = current_time - state[:last_action_time]
        if inactive_time > (threshold_minutes * 60)
          stuck_battles << {
            battle_id: battle_id,
            participants: state[:participants],
            inactive_minutes: (inactive_time / 60).to_i,
            type: state[:type]
          }
        end
      end
      
      stuck_battles
    end

    private

    def format_duration(seconds)
      hours = seconds / 3600
      minutes = (seconds % 3600) / 60
      secs = seconds % 60
      
      if hours > 0
        "#{hours.to_i}시간 #{minutes.to_i}분"
      elsif minutes > 0
        "#{minutes.to_i}분 #{secs.to_i}초"
      else
        "#{secs.to_i}초"
      end
    end
  end
end

# 정기적으로 만료된 전투 정리하는 백그라운드 태스크
class BattleCleanupTask
  def self.start
    @cleanup_thread = Thread.new do
      loop do
        sleep 300  # 5분마다 실행
        begin
          cleaned = BattleState.cleanup_expired_battles
          puts "[전투 정리] #{cleaned}개의 만료된 전투를 정리했습니다." if cleaned > 0
          
          # 멈춘 전투 감지
          stuck_battles = BattleState.detect_stuck_battles(30)
          if stuck_battles.any?
            puts "[경고] #{stuck_battles.size}개의 멈춘 전투가 감지되었습니다:"
            stuck_battles.each do |battle_info|
              puts "  - #{battle_info[:battle_id]}: #{battle_info[:participants].join(', ')} (#{battle_info[:inactive_minutes]}분 비활성)"
            end
          end
          
        rescue => e
          puts "[전투 정리 오류] #{e.message}"
        end
      end
    end
  end

  def self.stop
    @cleanup_thread&.kill
    @cleanup_thread = nil
  end
end
