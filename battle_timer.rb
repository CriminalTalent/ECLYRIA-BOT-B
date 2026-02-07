require_relative 'core/battle_state'
require_relative 'core/battle_engine'

class BattleTimer
  TEAM_NAMES = {
    team1: "불사조 기사단",
    team2: "이그드라실"
  }

  def initialize(mastodon_client, sheet_manager)
    @mastodon_client = mastodon_client
    @sheet_manager = sheet_manager
    @running = false
    @engine = BattleEngine.new(mastodon_client, sheet_manager)
  end

  def start
    @running = true

    Thread.new do
      while @running
        sleep 30 # 30초마다 체크
        check_all_battles
      end
    end

    puts "[타이머] 전투 시간 제한 감시 시작"
  end

  def stop
    @running = false
  end

  private

  def check_all_battles
    timeouts = BattleState.check_timeouts

    timeouts.each do |timeout_info|
      battle_id = timeout_info[:id]
      state = BattleState.get(battle_id)
      next unless state

      if timeout_info[:type] == :battle_timeout
        handle_battle_timeout(battle_id, state)
      elsif timeout_info[:type] == :turn_timeout
        handle_turn_timeout(battle_id, state)
      end
    end

    # 오래된 전투 정리
    cleaned = BattleState.cleanup_stalled_battles
    puts "[타이머] 오래된 전투 #{cleaned}개 정리" if cleaned > 0
  end

  # 턴 시간 초과 처리 (4분) - 동시 행동 방식
  def handle_turn_timeout(battle_id, state)
    # 아직 행동하지 않은 참가자 목록
    alive_participants = get_alive_participants(state)
    acted_users = (state[:actions_queue] || []).map { |a| a[:user_id] }
    not_acted = alive_participants.reject { |pid| acted_users.include?(pid) }

    return if not_acted.empty?

    not_acted_names = not_acted.map do |pid|
      user = @sheet_manager.find_user(pid)
      user ? (user["이름"] || pid) : pid
    end

    puts "[타이머] #{battle_id}: #{not_acted_names.join(', ')} 턴 시간 초과 (4분) - 자동 방어"

    # BattleEngine의 auto_defend_timeout 호출
    @engine.auto_defend_timeout(battle_id, state)
  end

  # 전투 시간 초과 처리 (1시간)
  def handle_battle_timeout(battle_id, state)
    puts "[타이머] #{battle_id}: 전투 시간 초과 (1시간) - HP 합산으로 승부 결정"

    # BattleEngine의 end_battle_by_hp_total 호출
    @engine.end_battle_by_hp_total(battle_id, state)
  end

  # 생존 참가자 목록
  def get_alive_participants(state)
    state[:participants].select do |pid|
      user = @sheet_manager.find_user(pid)
      user && (user["HP"] || 0).to_i > 0
    end
  end
end
