# core/battle_state.rb
# 이모지 제거 버전

class BattleState
  @@battles = {}
  @@battle_counter = 0

  class << self
    def create(state_data)
      @@battle_counter += 1
      battle_id = "battle_#{@@battle_counter}_#{Time.now.to_i}"
      
      # 기본 시간 정보 추가
      state_data[:battle_start_time] ||= Time.now
      state_data[:last_action_time] ||= Time.now
      state_data[:battle_id] = battle_id
      
      @@battles[battle_id] = state_data
      
      # 참가자별 인덱스 생성 (빠른 검색을 위해)
      if state_data[:participants]
        state_data[:participants].each do |participant_id|
          @@battles["participant_#{participant_id}"] = { battle_id: battle_id, state: state_data }
        end
      end
      
      puts "[전투 상태] 생성: #{battle_id} (참가자: #{state_data[:participants]&.join(', ')})"
      battle_id
    end

    def get(battle_id = nil)
      return @@battles if battle_id.nil?
      @@battles[battle_id]
    end

    def get_all_battles
      # 실제 전투 ID만 반환 (participant_ 접두사가 없는 것들)
      @@battles.select { |k, v| !k.start_with?("participant_") && v.is_a?(Hash) }
    end

    def update(battle_id, state_data)
      return false unless @@battles[battle_id]
      
      # 마지막 액션 시간 업데이트
      state_data[:last_action_time] = Time.now
      state_data[:battle_id] = battle_id
      
      @@battles[battle_id] = state_data
      
      # 참가자별 인덱스도 업데이트
      if state_data[:participants]
        state_data[:participants].each do |participant_id|
          @@battles["participant_#{participant_id}"] = { battle_id: battle_id, state: state_data }
        end
      end
      
      true
    end

    def clear(battle_id)
      state = @@battles[battle_id]
      return false unless state
      
      # 참가자별 인덱스 삭제
      if state[:participants]
        state[:participants].each do |participant_id|
          @@battles.delete("participant_#{participant_id}")
        end
      end
      
      @@battles.delete(battle_id)
      puts "[전투 상태] 삭제: #{battle_id}"
      true
    end

    # 기존 메소드명 유지 (find_by_participant)
    def find_by_participant(user_id)
      participant_data = @@battles["participant_#{user_id}"]
      participant_data ? participant_data[:state] : nil
    end

    def find_battle_id_by_participant(user_id)
      participant_data = @@battles["participant_#{user_id}"]
      participant_data ? participant_data[:battle_id] : nil
    end

    # 하위 호환성을 위한 별칭
    alias_method :find_by_user, :find_by_participant
    alias_method :find_battle_id_by_user, :find_battle_id_by_participant

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
        elsif state[:actions]
          completed = state[:actions].size
          total = state[:participants]&.size || 0
          result += "   행동 선택: #{completed}/#{total}\n"
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

    # 전투 상태별 통계
    def get_battle_status_summary
      all_battles = get_all_battles
      summary = {
        pvp: { count: 0, avg_duration: 0 },
        team_2v2: { count: 0, avg_duration: 0 },
        team_4v4: { count: 0, avg_duration: 0 },
        waiting_actions: 0,
        stuck_battles: 0
      }
      
      current_time = Time.now
      stuck_threshold = 30 * 60 # 30분
      
      all_battles.each do |battle_id, state|
        type_key = case state[:type]
                   when "pvp" then :pvp
                   when "2v2" then :team_2v2
                   when "4v4" then :team_4v4
                   else :pvp
                   end
        
        summary[type_key][:count] += 1
        
        if state[:battle_start_time]
          duration = current_time - state[:battle_start_time]
          summary[type_key][:avg_duration] += duration
        end
        
        # 대기 중인 액션 확인
        if state[:actions] && state[:participants]
          completed_actions = state[:actions].size
          total_participants = state[:participants].size
          if completed_actions < total_participants
            summary[:waiting_actions] += 1
          end
        end
        
        # 멈춘 전투 확인
        if state[:last_action_time]
          inactive_time = current_time - state[:last_action_time]
          if inactive_time > stuck_threshold
            summary[:stuck_battles] += 1
          end
        end
      end
      
      # 평균 지속시간 계산
      [:pvp, :team_2v2, :team_4v4].each do |type|
        if summary[type][:count] > 0
          summary[type][:avg_duration] /= summary[type][:count]
          summary[type][:avg_duration] = summary[type][:avg_duration].to_i
        end
      end
      
      summary
    end

    # 전투 강제 종료 (관리자용)
    def force_end_battle(battle_id, reason = "관리자 종료")
      state = get(battle_id)
      return false unless state
      
      participants = state[:participants] || []
      puts "[강제 종료] 전투 #{battle_id} 종료 - #{reason}"
      puts "[강제 종료] 참가자: #{participants.join(', ')}"
      
      clear(battle_id)
      true
    end

    # 사용자의 모든 전투 강제 종료
    def force_end_user_battles(user_id, reason = "사용자 요청")
      ended_battles = []
      
      # 해당 사용자가 참가한 모든 전투 찾기
      get_all_battles.each do |battle_id, state|
        if state[:participants]&.include?(user_id)
          if force_end_battle(battle_id, reason)
            ended_battles << battle_id
          end
        end
      end
      
      ended_battles
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

  def self.status
    {
      running: @cleanup_thread&.alive? == true,
      battles: BattleState.get_battle_status_summary
    }
  end
end
