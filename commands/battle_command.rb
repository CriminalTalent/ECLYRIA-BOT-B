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
    # ============================
    # 1:1 전투 시작
    # [전투 Snow_White vs Bridget]
    # ============================
    when /\A\[전투\s+@?(\S+)\s+vs\s+@?(\S+)\]\z/i
      raw1, raw2 = $1, $2
      puts "[BattleCommand] regex captures: #{raw1.inspect}, #{raw2.inspect}"

      u1 = sanitize.call(raw1)
      u2 = sanitize.call(raw2)

      if u1.empty? || u2.empty?
        puts "[BattleCommand] invalid 1v1 args: u1=#{u1.inspect}, u2=#{u2.inspect}"
        @mastodon_client.reply(reply_status, "@#{user_id} 전투 참가자를 인식하지 못했습니다.")
        return
      end

      # 참가자 중 누가 이미 전투 중이면 거절
      if BattleState.player_in_battle?(u1) || BattleState.player_in_battle?(u2)
        @mastodon_client.reply(
          reply_status,
          "@#{user_id} 이미 전투에 참여 중인 플레이어가 있어 이 조합으로는 전투를 시작할 수 없습니다."
        )
        return
      end

      puts "[BattleCommand] -> start_1v1 #{u1} vs #{u2}"
      @engine.start_1v1(u1, u2, reply_status)

    # ============================
    # 2:2 다인 전투 시작
    # [다인전투/@A/@B/@C/@D]
    # ============================
    when /\A\[다인전투\/@?(\S+)\/@?(\S+)\/@?(\S+)\/@?(\S+)\]\z/i
      a, b, c, d = $1, $2, $3, $4
      u1, u2, u3, u4 = [a, b, c, d].map { |x| sanitize.call(x) }

      if [u1, u2, u3, u4].any?(&:empty?)
        puts "[BattleCommand] invalid 2v2 args: #{[u1, u2, u3, u4].inspect}"
        @mastodon_client.reply(reply_status, "@#{user_id} 다인전투 참가자를 인식하지 못했습니다.")
        return
      end

      # 4인 중 한 명이라도 이미 전투 중이면 거절
      if [u1, u2, u3, u4].any? { |p| BattleState.player_in_battle?(p) }
        @mastodon_client.reply(
          reply_status,
          "@#{user_id} 이미 전투에 참여 중인 플레이어가 있어서 이 조합으로는 다인전투를 시작할 수 없습니다."
        )
        return
      end

      puts "[BattleCommand] -> start_2v2 #{u1}, #{u2} vs #{u3}, #{u4}"
      @engine.start_2v2(u1, u2, u3, u4, reply_status)

    # ============================
    # 공격
    # ============================
    when /\[공격\/@?(\S+)\]/i
      target = sanitize.call($1)
      puts "[BattleCommand] -> attack with target: #{target}"
      @engine.attack(user_id, target)

    when /\[공격\]/i
      puts "[BattleCommand] -> attack (no target)"
      @engine.attack(user_id)

    # ============================
    # 방어
    # ============================
    when /\[방어\/@?(\S+)\]/i
      target = sanitize.call($1)
      puts "[BattleCommand] -> defend target: #{target}"
      @engine.defend_target(user_id, target)

    when /\[방어\]/i
      puts "[BattleCommand] -> defend"
      @engine.defend(user_id)

    # ============================
    # 반격 / 도주
    # ============================
    when /\[반격\]/i
      puts "[BattleCommand] -> counter"
      @engine.counter(user_id)

    when /\[도주\]/i
      puts "[BattleCommand] -> flee"
      @engine.flee(user_id)

    # ============================
    # 허수아비 (연습전)
    # [허수아비 하/중/상]
    # ============================
    when /\[허수아비\s*(하|중|상)\]/i
      diff = Regexp.last_match(1)
      if BattleState.player_in_battle?(user_id)
        @mastodon_client.reply(
          reply_status,
          "@#{user_id} 이미 다른 전투에 참여 중이라 허수아비 연습전은 시작할 수 없습니다."
        )
        return
      end
      puts "[BattleCommand] -> dummy #{diff}"
      @engine.start_dummy_battle(user_id, diff, reply_status)

    else
      puts "[BattleCommand] unknown: #{text}"
    end
  end
end
