# core/battle_state.rb

module BattleState
  module_function

  # 전투 상태 저장
  @@state = {
    players: [],      
    team_a: [],       
    team_b: [],       
    turn: nil,        
    scarecrow: false, 
    difficulty: nil,
    battle_context: nil  # 전투 시작 컨텍스트 추가 ('dm' or 'timeline')
  }

  @@mastodon_client = nil
  @@turn_timer = nil

  def set_mastodon_client(client)
    @@mastodon_client = client
  end

  def set(players:, team_a: nil, team_b: nil, turn: nil, scarecrow: false, difficulty: nil, context: nil)
    @@state[:players] = players
    @@state[:team_a] = team_a || []
    @@state[:team_b] = team_b || []
    @@state[:turn] = turn
    @@state[:scarecrow] = scarecrow
    @@state[:difficulty] = difficulty
    @@state[:battle_context] = context || 'timeline'  # 기본값 타임라인
  end

  def set_turn(user_id)
    cancel_turn_timer
    
    @@state[:turn] = user_id
    
    unless user_id.include?("허수아비")
      start_turn_timer(user_id)
    end
  end

  def start_turn_timer(user_id)
    @@turn_timer = Thread.new do
      sleep(300)
      
      if @@state[:turn] == user_id && !@@state[:players].empty?
        say("#{user_id}님이 5분간 응답이 없어 턴이 자동으로 넘어갑니다.")
        next_turn
      end
    end
  end

  def cancel_turn_timer
    if @@turn_timer && @@turn_timer.alive?
      @@turn_timer.kill
      @@turn_timer = nil
    end
  end

  def next_turn
    return unless @@state[:turn] && !@@state[:players].empty?
    
    cancel_turn_timer
    
    current_index = @@state[:players].index(@@state[:turn])
    return unless current_index
    
    next_index = (current_index + 1) % @@state[:players].length
    next_player = @@state[:players][next_index]
    
    @@state[:turn] = next_player
    
    unless next_player.include?("허수아비")
      start_turn_timer(next_player)
    end
  end

  def get_turn
    @@state[:turn]
  end

  def is_current_turn?(user_id)
    @@state[:turn] == user_id
  end

  def get_opponent(user_id)
    if !@@state[:team_a].empty? && !@@state[:team_b].empty?
      if @@state[:team_a].include?(user_id)
        return @@state[:team_b].first
      else
        return @@state[:team_a].first
      end
    else
      others = @@state[:players] - [user_id]
      others.first
    end
  end

  def in_battle?(user_id)
    @@state[:players].include?(user_id)
  end

  def get_context
    @@state[:battle_context] || 'timeline'
  end

  def say(message)
    context = get_context
    
    # 컨텍스트에 따라 알림 방식 결정
    if context == 'dm'
      # DM으로 시작된 전투는 DM으로만 알림
      if @@mastodon_client && !@@state[:players].empty?
        @@state[:players].each do |player|
          unless player.include?("허수아비")
            @@mastodon_client.dm(player, message)
          end
        end
      end
    else
      # 타임라인으로 시작된 전투는 타임라인으로만 알림
      if @@mastodon_client
        @@mastodon_client.say(message)
      else
        puts "[BATTLE] #{message}"
      end
    end
  end

  def clear
    cancel_turn_timer
    @@state = {
      players: [],
      team_a: [],
      team_b: [],
      turn: nil,
      scarecrow: false,
      difficulty: nil,
      battle_context: nil
    }
  end

  def get_players
    @@state[:players]
  end

  def get_teams
    {
      team_a: @@state[:team_a],
      team_b: @@state[:team_b]
    }
  end

  def is_scarecrow_battle?
    @@state[:scarecrow]
  end

  def get_difficulty
    @@state[:difficulty]
  end
end
