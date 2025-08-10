# core/battle_state.rb

module BattleState
  module_function

  # 전투 상태 저장
  @@state = {
    players: [],      # 전체 참가자 ID 목록
    team_a: [],       # 팀 A
    team_b: [],       # 팀 B
    turn: nil,        # 현재 턴인 사용자 ID
    scarecrow: false, # 허수아비 전투 여부
    difficulty: nil   # 허수아비 난이도
  }

  @@mastodon_client = nil

  def set_mastodon_client(client)
    @@mastodon_client = client
  end

  def set(players:, team_a: nil, team_b: nil, turn: nil, scarecrow: false, difficulty: nil)
    @@state[:players] = players
    @@state[:team_a] = team_a || []
    @@state[:team_b] = team_b || []
    @@state[:turn] = turn
    @@state[:scarecrow] = scarecrow
    @@state[:difficulty] = difficulty
  end

  def set_turn(user_id)
    @@state[:turn] = user_id
  end

  def next_turn
    return unless @@state[:turn] && !@@state[:players].empty?
    
    current_index = @@state[:players].index(@@state[:turn])
    return unless current_index
    
    next_index = (current_index + 1) % @@state[:players].length
    @@state[:turn] = @@state[:players][next_index]
  end

  def get_turn
    @@state[:turn]
  end

  def is_current_turn?(user_id)
    @@state[:turn] == user_id
  end

  def get_opponent(user_id)
    # 팀 전투인 경우
    if !@@state[:team_a].empty? && !@@state[:team_b].empty?
      if @@state[:team_a].include?(user_id)
        # A팀 소속이면 B팀에서 체력이 남은 첫 번째 플레이어 반환
        return @@state[:team_b].first
      else
        # B팀 소속이면 A팀에서 체력이 남은 첫 번째 플레이어 반환
        return @@state[:team_a].first
      end
    else
      # 일반 1:1 전투 (허수아비 포함)
      others = @@state[:players] - [user_id]
      others.first
    end
  end

  def in_battle?(user_id)
    @@state[:players].include?(user_id)
  end

  def say(message)
    # 1. 공개 타임라인에 포스트
    if @@mastodon_client
      @@mastodon_client.say(message)
    else
      puts "[BATTLE] #{message}"
    end

    # 2. 전투 참가자들에게 DM 발송 (허수아비 제외)
    if @@mastodon_client && !@@state[:players].empty?
      @@state[:players].each do |player|
        # 허수아비는 DM 제외
        unless player.include?("허수아비")
          @@mastodon_client.dm(player, message)
        end
      end
    end
  end

  def end
    @@state = {
      players: [],
      team_a: [],
      team_b: [],
      turn: nil,
      scarecrow: false,
      difficulty: nil
    }
  end

  def current_state
    @@state
  end
end
