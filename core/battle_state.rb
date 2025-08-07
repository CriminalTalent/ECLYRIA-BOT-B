# core/battle_state.rb

require_relative './sheet_manager'

module BattleState
  module_function

  # 전투 상태 저장
  @@state = {
    players: [],      # 전체 참가자 ID 목록
    team_a: [],       # 팀 A
    team_b: [],       # 팀 B
    turn: nil,        # 현재 턴인 사용자 ID
    sheet: nil        # 시트 객체 저장
  }

  def set(players:, team_a: nil, team_b: nil, turn: nil, sheet:)
    @@state[:players] = players
    @@state[:team_a] = team_a || []
    @@state[:team_b] = team_b || []
    @@state[:turn] = turn
    @@state[:sheet] = sheet
  end

  def set_turn(user_id)
    @@state[:turn] = user_id
  end

  def next_turn
    current_index = @@state[:players].index(@@state[:turn])
    next_index = (current_index + 1) % @@state[:players].length
    @@state[:turn] = @@state[:players][next_index]
  end

  def get_turn
    @@state[:turn]
  end

  def get_opponent(user_id)
    others = @@state[:players] - [user_id]
    others.first # 단순 1:1 전투 기준
  end

  def in_battle?(user_id)
    @@state[:players].include?(user_id)
  end

  def say(message)
    # 마스토돈 API로 출력 (main.rb에서 client 참조 전달 시 확장 가능)
    puts "[BATTLE] #{message}"
  end

  def end
    @@state = {
      players: [],
      team_a: [],
      team_b: [],
      turn: nil,
      sheet: nil
    }
  end

  def current_state
    @@state
  end
end
