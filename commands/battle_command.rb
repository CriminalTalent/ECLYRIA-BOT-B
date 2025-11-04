require_relative '../core/battle_engine'

class BattleCommand
  def initialize(mastodon_client, sheet_manager)
    @mastodon_client = mastodon_client
    @sheet_manager = sheet_manager
    @battle_engine = BattleEngine.new(mastodon_client, sheet_manager)
  end

  def handle_command(user_id, content, reply_id)
    case content
    when /\[전투\s+(\S+)\s+vs\s+(\S+)\]/i
      user1 = Regexp.last_match(1)
      user2 = Regexp.last_match(2)
      @battle_engine.start_1v1(user1, user2, reply_id)

    when /\[전투\s+(\S+)\s+(\S+)\s+vs\s+(\S+)\s+(\S+)\]/i
      user1 = Regexp.last_match(1)
      user2 = Regexp.last_match(2)
      user3 = Regexp.last_match(3)
      user4 = Regexp.last_match(4)
      @battle_engine.start_2v2(user1, user2, user3, user4, reply_id)

    when /\[허수아비\s*(하|중|상)\]/i
      difficulty = Regexp.last_match(1)
      @battle_engine.start_dummy_battle(user_id, difficulty, reply_id)

    when /\[공격\]/i
      @battle_engine.attack(user_id)

    when /\[방어\]/i
      @battle_engine.defend(user_id)

    when /\[반격\]/i
      @battle_engine.counter(user_id)

    when /\[도망\]/i
      @battle_engine.flee(user_id)

    else
      @mastodon_client.reply(reply_id, "알 수 없는 전투 명령입니다.", visibility: 'direct')
    end
  end
end
