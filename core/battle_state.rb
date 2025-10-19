# core/battle_state.rb
module BattleState
  module_function

  @@state = {}
  @@mastodon_client = nil

  def set_mastodon_client(client)
    @@mastodon_client = client
  end

  def set(data)
    @@state.merge!(data)
  end

  def get(key)
    @@state[key]
  end

  def clear
    @@state.clear
  end

  def set_turn(player)
    @@state[:turn] = player
  end

  def get_turn
    @@state[:turn]
  end

  def is_current_turn?(player)
    @@state[:turn] == player
  end

  def next_turn
    players = @@state[:players] || []
    return if players.empty?
    
    current = @@state[:turn]
    idx = players.index(current)
    return unless idx
    
    next_idx = (idx + 1) % players.size
    @@state[:turn] = players[next_idx]
  end

  def get_opponent(player)
    players = @@state[:players] || []
    players.find { |p| p != player }
  end

  def in_battle?(player)
    players = @@state[:players] || []
    players.include?(player)
  end

  def end
    @@state.clear
  end

  def cancel_turn_timer
    # 턴 타이머가 있다면 취소 (현재는 구현되지 않음)
  end

  def get_context
    @@state[:context] || 'timeline'
  end

  def say(message)
    context = get_context
    
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
      # 타임라인으로 시작된 전투는 참여자들에게 멘션으로 알림
      if @@mastodon_client
        players = @@state[:players] || []
        human_players = players.reject { |p| p.include?("허수아비") }
        
        if human_players.any?
          mentions = human_players.map { |p| "@#{p}" }.join(" ")
          @@mastodon_client.say("#{mentions}\n#{message}")
        else
          @@mastodon_client.say(message)
        end
      else
        puts "[BATTLE] #{message}"
      end
    end
  end
end
