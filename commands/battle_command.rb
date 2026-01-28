require_relative '../core/battle_state'
require_relative '../core/battle_engine'

class BattleCommand
  def initialize(mastodon_client, sheet_manager)
    @mastodon_client = mastodon_client
    @sheet_manager   = sheet_manager
    @engine          = BattleEngine.new(mastodon_client, sheet_manager)
  end

  def handle_command(user_id, text, reply_status)
    puts "[BattleCommand] handle_command: #{text} from #{user_id}"

    sanitize = ->(s) { s.to_s.gsub(/\p{Cf}/, '').strip.sub(/\A@+/, '') }

    case text
    when /\A\[전투\s+@?(\S+)\s+vs\s+@?(\S+)\]\z/i
      raw1, raw2 = $1, $2
      u1 = sanitize.call(raw1)
      u2 = sanitize.call(raw2)
      @engine.start_1v1(u1, u2, reply_status) unless u1.empty? || u2.empty?

    when /\A\[다인전투\/@?(\S+)\/@?(\S+)\/@?(\S+)\/@?(\S+)\]\z/i
      a, b, c, d = $1, $2, $3, $4
      u1, u2, u3, u4 = [a, b, c, d].map { |x| sanitize.call(x) }
      @engine.start_2v2(u1, u2, u3, u4, reply_status) if [u1, u2, u3, u4].none?(&:empty?)

    when /\[공격\/@?(\S+)\]/i
      @engine.attack(user_id, sanitize.call($1))

    when /\[공격\]/i
      @engine.attack(user_id)

    when /\[방어\/@?(\S+)\]/i
      @engine.defend_target(user_id, sanitize.call($1))

    when /\[방어\]/i
      @engine.defend(user_id)

    when /\[반격\]/i
      @engine.counter(user_id)

    when /\[도주\]/i
      @engine.flee(user_id)

    when /\[허수아비\s*(하|중|상)\]/i
      @engine.start_dummy_battle(user_id, $1, reply_status)
    end
  end
end
