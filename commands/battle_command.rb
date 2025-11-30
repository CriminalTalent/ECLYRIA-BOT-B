require_relative '../core/battle_engine'

class BattleCommand
  def initialize(mastodon_client, sheet_manager)
    @mastodon_client = mastodon_client
    @sheet_manager = sheet_manager
    @engine = BattleEngine.new(mastodon_client, sheet_manager)
  end

  def handle_command(user_id, text, reply_status)
    puts "[BattleCommand] handle_command: #{text} from #{user_id}"
    
    sanitize = ->(s) { s.to_s.gsub(/\p{Cf}/, '').strip.sub(/\A@+/, '') }
    
    case text
    when /\A\[전투\s+@?(\S+)\s+vs\s+@?(\S+)\]\z/i
      raw1, raw2 = $1, $2
      puts "[BattleCommand] regex captures: #{raw1.inspect}, #{raw2.inspect}"
      u1 = sanitize.call(raw1)
      u2 = sanitize.call(raw2)
      if u1.empty? || u2.empty?
        puts "[BattleCommand] invalid 1v1 args: u1=#{u1.inspect}, u2=#{u2.inspect}"
        return
      end

      # 전투 중복 참가 방지: 참가자 중 이미 전투 중인 사람이 있으면 막기
      conflicted = [u1, u2].find { |id| user_in_battle?(id) }
      if conflicted
        @mastodon_client.reply(reply_status, "@#{conflicted} 이미 전투 중입니다! 먼저 전투를 마치세요.")
        puts "[BattleCommand] blocked start_1v1: #{conflicted} already in battle"
        return
      end

      puts "[BattleCommand] -> start_1v1 #{u1} vs #{u2}"
      @engine.start_1v1(u1, u2, reply_status)
    
    when /\A\[다인전투\/@?(\S+)\/@?(\S+)\/@?(\S+)\/@?(\S+)\]\z/i
      a, b, c, d = $1, $2, $3, $4
      u1, u2, u3, u4 = [a, b, c, d].map { |x| sanitize.call(x) }
      if [u1, u2, u3, u4].any?(&:empty?)
        puts "[BattleCommand] invalid 2v2 args: #{[u1, u2, u3, u4].inspect}"
        return
      end

      # 전투 중복 참가 방지: 네 명 중 이미 전투 중인 사람이 있으면 막기
      conflicted = [u1, u2, u3, u4].find { |id| user_in_battle?(id) }
      if conflicted
        @mastodon_client.reply(reply_status, "@#{conflicted} 이미 전투 중입니다! 먼저 전투를 마치세요.")
        puts "[BattleCommand] blocked start_2v2: #{conflicted} already in battle"
        return
      end

      puts "[BattleCommand] -> start_2v2 #{u1}, #{u2} vs #{u3}, #{u4}"
      @engine.start_2v2(u1, u2, u3, u4, reply_status)
    
    when /\[공격\/@?(\S+)\]/i
      target = sanitize.call($1)
      puts "[BattleCommand] -> attack with target: #{target}"
      @engine.attack(user_id, target)
    
    when /\[공격\]/i
      puts "[BattleCommand] -> attack (no target)"
      @engine.attack(user_id)
    
    when /\[방어\/@?(\S+)\]/i
      target = sanitize.call($1)
      puts "[BattleCommand] -> defend target: #{target}"
      @engine.defend_target(user_id, target)
    
    when /\[방어\]/i
      puts "[BattleCommand] -> defend"
      @engine.defend(user_id)
    
    when /\[반격\]/i
      puts "[BattleCommand] -> counter"
      @engine.counter(user_id)
    
    when /\[도주\]/i
      puts "[BattleCommand] -> flee"
      @engine.flee(user_id)
    
    when /\[허수아비\s*(하|중|상)\]/i
      diff = Regexp.last_match(1)
      puts "[BattleCommand] -> dummy #{diff}"

      # 허수아비 전투도 "한 사람 한 전투" 원칙 적용
      if user_in_battle?(user_id)
        @mastodon_client.reply(reply_status, "@#{user_id} 이미 전투 중입니다! 먼저 전투를 마치세요.")
        puts "[BattleCommand] blocked dummy battle: #{user_id} already in battle"
        return
      end

      @engine.start_dummy_battle(user_id, diff, reply_status)
    
    else
      puts "[BattleCommand] unknown: #{text}"
    end
  rescue => e
    puts "[BattleCommand] 오류: #{e.class}: #{e.message}"
    puts e.backtrace.first(5)
    @mastodon_client.reply(reply_status, "전투 명령 처리 중 오류가 발생했습니다.")
  end

  private

  # 주어진 ID가 이미 어떤 전투에 참가 중인지 확인
  # - BattleState.find_by_user(id)가 있으면 그걸 우선 사용
  # - 없으면 기존 단일 상태(BattleState.get)의 participants 기준으로 확인
  def user_in_battle?(user_id)
    begin
      if defined?(BattleState) && BattleState.respond_to?(:find_by_user)
        !!BattleState.find_by_user(user_id)
      else
        if defined?(BattleState) && BattleState.respond_to?(:get)
          state = BattleState.get
          return false unless state
          participants = state[:participants] || []
          participants.respond_to?(:include?) && participants.include?(user_id)
        else
          false
        end
      end
    rescue => e
      puts "[BattleCommand] user_in_battle? 체크 중 오류: #{e.class}: #{e.message}"
      false
    end
  end
end
