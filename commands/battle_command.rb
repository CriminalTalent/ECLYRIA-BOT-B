require_relative '../core/battle_engine'

class BattleCommand
  def initialize(mastodon_client, sheet_manager)
    @mastodon_client = mastodon_client
    @sheet_manager = sheet_manager
    @engine = BattleEngine.new(mastodon_client, sheet_manager)
  end

  def handle_command(user_id, text, reply_status)
    puts "[BattleCommand] handle_command: #{text} from #{user_id}"
    
    # 아이디 정규화(맨앞 @ 제거 + 제어문자 제거)
    sanitize = ->(s) { s.to_s.gsub(/\p{Cf}/, '').strip.sub(/\A@+/, '') }
    
    case text
    # === 1:1 전투 ===
    when /\A\[전투\s+@?(\S+)\s+vs\s+@?(\S+)\]\z/i
      raw1, raw2 = $1, $2
      puts "[BattleCommand] regex captures: #{raw1.inspect}, #{raw2.inspect}"
      u1 = sanitize.call(raw1)
      u2 = sanitize.call(raw2)
      if u1.empty? || u2.empty?
        puts "[BattleCommand] invalid 1v1 args: u1=#{u1.inspect}, u2=#{u2.inspect}"
        return
      end
      puts "[BattleCommand] -> start_1v1 #{u1} vs #{u2}"
      @engine.start_1v1(u1, u2, reply_status)
    
    # === 2:2 전투 (다인전투) ===
    when /\A\[다인전투\s+@?(\S+)\s+@?(\S+)\s+vs\s+@?(\S+)\s+@?(\S+)\]\z/i
      a, b, c, d = $1, $2, $3, $4
      u1, u2, u3, u4 = [a, b, c, d].map { |x| sanitize.call(x) }
      if [u1, u2, u3, u4].any?(&:empty?)
        puts "[BattleCommand] invalid 2v2 args: #{[u1, u2, u3, u4].inspect}"
        return
      end
      puts "[BattleCommand] -> start_2v2 #{u1}, #{u2} vs #{u3}, #{u4}"
      @engine.start_2v2(u1, u2, u3, u4, reply_status)
    
    # === 타겟 지정 공격 (신규) ===
    when /\[공격\/@?(\S+)\]/i
      target = sanitize.call($1)
      puts "[BattleCommand] -> attack with target: #{target}"
      @engine.attack(user_id, target)
    
    # === 일반 공격 ===
    when /\[공격\]/i
      puts "[BattleCommand] -> attack (no target)"
      @engine.attack(user_id)
    
    # === 방어 ===
    when /\[방어\]/i
      puts "[BattleCommand] -> defend"
      @engine.defend(user_id)
    
    # === 반격 ===
    when /\[반격\]/i
      puts "[BattleCommand] -> counter"
      @engine.counter(user_id)
    
    # === 도주 ===
    when /\[도주\]/i
      puts "[BattleCommand] -> flee"
      @engine.flee(user_id)
    
    # === 허수아비 전투 ===
    when /\[허수아비\s*(하|중|상)\]/i
      diff = Regexp.last_match(1)
      puts "[BattleCommand] -> dummy #{diff}"
      @engine.start_dummy_battle(user_id, diff, reply_status)
    
    else
      puts "[BattleCommand] unknown: #{text}"
    end
  end
end
