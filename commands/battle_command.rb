require_relative '../core/battle_engine'
require_relative '../core/battle_state'

class BattleCommand
  def initialize(mastodon_client, sheet_manager)
    @mastodon_client = mastodon_client
    @sheet_manager = sheet_manager
    @battle_engine = BattleEngine.new(mastodon_client, sheet_manager)
  end

  def start_battle(text, user_id, reply_id)
    if BattleState.active?
      @mastodon_client.reply(reply_id, "이미 진행 중인 전투가 있습니다.", visibility: 'public')
      return
    end

    mentions = text.scan(/@([^@\s]+@[^\s]+)/).flatten
    
    if mentions.length == 1
      opponent_id = "@#{mentions[0]}"
      @battle_engine.start_1v1(user_id, opponent_id, reply_id)
    elsif mentions.length == 3
      teammate_id = "@#{mentions[0]}"
      opponent1_id = "@#{mentions[1]}"
      opponent2_id = "@#{mentions[2]}"
      @battle_engine.start_2v2(user_id, teammate_id, opponent1_id, opponent2_id, reply_id)
    else
      @mastodon_client.reply(reply_id, 
        "전투 형식이 올바르지 않습니다.\n" +
        "1:1 전투: [전투개시/@상대방]\n" +
        "2:2 전투: [전투개시/@우리팀/@상대방1/@상대방2]",
        visibility: 'public')
    end
  end

  def start_dummy_battle(text, user_id, reply_id)
    if BattleState.active?
      @mastodon_client.reply(reply_id, "이미 진행 중인 전투가 있습니다.", visibility: 'public')
      return
    end

    match = text.match(/\[허수아비\s+(상|중|하)\]/i)
    difficulty = match[1]
    
    @battle_engine.start_dummy_battle(user_id, difficulty, reply_id)
  end

  def handle_action(text, user_id, reply_id)
    unless BattleState.active?
      @mastodon_client.reply(reply_id, "진행 중인 전투가 없습니다.", visibility: 'direct')
      return
    end

    if text.match(/\[공격\]/i)
      @battle_engine.attack(user_id)
    elsif text.match(/\[방어\]/i)
      @battle_engine.defend(user_id)
    elsif text.match(/\[반격\]/i)
      @battle_engine.counter(user_id)
    elsif text.match(/\[도주\]/i)
      @battle_engine.flee(user_id)
    end
  end
end
