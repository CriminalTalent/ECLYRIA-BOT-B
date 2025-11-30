# core/battle_engine.rb
# 멀티 전투 + 플레이어 중복 참여 방지 안정 버전

require_relative 'battle_state'

class BattleEngine
  DEFAULT_HP = 100

  def initialize(mastodon_client, sheet_manager)
    @mastodon_client = mastodon_client
    @sheet_manager   = sheet_manager
  end

  # =============================
  #  1:1 전투 시작
  # =============================
  def start_1v1(user1, user2, reply_status)
    puts "[BattleEngine] start_1v1 요청: #{user1} vs #{user2}"

    # 한 플레이어는 하나의 전투만 참여 가능
    if BattleState.player_in_battle?(user1) || BattleState.player_in_battle?(user2)
      msg = "@#{user1} @#{user2} 이미 진행 중인 전투가 있습니다. 먼저 기존 전투를 종료해 주세요."
      @mastodon_client.reply(reply_status, msg)
      return
    end

    battle_id  = build_battle_id(user1, user2)
    turn_order = [user1, user2].shuffle
    current    = turn_order.first

    state = {
      type:         '1v1',
      battle_id:    battle_id,
      players:      [user1, user2],
      hp:           { user1 => DEFAULT_HP, user2 => DEFAULT_HP },
      turn_order:   turn_order,
      current_turn: current,
      root_status:  reply_status
    }

    BattleState.set(battle_id, state)

    puts "[디버그] start_1v1: turn_order=#{turn_order.inspect}"
    puts "[디버그] start_1v1: current_turn=#{current} (String)"

    text = <<~TXT.strip
      ∴ 전투 개시!
      - 참가자: @#{user1} vs @#{user2}
      - 선공: @#{current}
      - 시작 HP: #{DEFAULT_HP} / #{DEFAULT_HP}

      현재 턴: @#{current}
      행동: [공격] / [방어] / [도주]
    TXT

    @mastodon_client.reply_with_mentions(reply_status, text, [user1, user2])
  end

  # =============================
  #  2:2 전투 시작 (형식만 유지)
  # =============================
  def start_2v2(a, b, c, d, reply_status)
    puts "[BattleEngine] start_2v2 요청: #{a}, #{b} vs #{c}, #{d}"

    # 네 명 중 한 명이라도 이미 전투 중이면 거절
    [a, b, c, d].each do |u|
      if BattleState.player_in_battle?(u)
        msg = "@#{u} 이미 다른 전투에 참여 중입니다. 먼저 기존 전투를 종료해 주세요."
        @mastodon_client.reply(reply_status, msg)
        return
      end
    end

    battle_id  = build_battle_id(a, b, c, d)
    players    = [a, b, c, d]
    turn_order = players.shuffle
    current    = turn_order.first

    hp_hash = {}
    players.each { |p| hp_hash[p] = DEFAULT_HP }

    state = {
      type:         '2v2',
      battle_id:    battle_id,
      players:      players,
      hp:           hp_hash,
      turn_order:   turn_order,
      current_turn: current,
      root_status:  reply_status
    }

    BattleState.set(battle_id, state)

    puts "[디버그] start_2v2: turn_order=#{turn_order.inspect}"
    puts "[디버그] start_2v2: current_turn=#{current} (String)"

    text = <<~TXT.strip
      ∴ 2:2 전투 개시!
      - 팀1: @#{a}, @#{b}
      - 팀2: @#{c}, @#{d}
      - 선공: @#{current}
      - 시작 HP: #{DEFAULT_HP} x 4

      현재 턴: @#{current}
      행동: [공격] / [방어] / [도주]
    TXT

    @mastodon_client.reply_with_mentions(reply_status, text, players)
  end

  # =============================
  #  허수아비 전투 (훈련용)
  # =============================
  def start_dummy_battle(user_id, diff, reply_status)
    puts "[BattleEngine] start_dummy_battle 요청: #{user_id}, 난이도=#{diff}"

    if BattleState.player_in_battle?(user_id)
      msg = "@#{user_id} 이미 다른 전투에 참여 중입니다. 먼저 기존 전투를 종료해 주세요."
      @mastodon_client.reply(reply_status, msg)
      return
    end

    dummy_name =
      case diff
      when '하' then "허수아비(하)"
      when '중' then "허수아비(중)"
      when '상' then "허수아비(상)"
      else "허수아비"
      end

    battle_id  = build_battle_id(user_id, dummy_name, "dummy")
    turn_order = [user_id, dummy_name]  # 훈련용은 플레이어 선공 고정도 가능하지만 일단 그대로
    current    = user_id

    state = {
      type:         'dummy',
      battle_id:    battle_id,
      players:      [user_id, dummy_name],
      hp:           { user_id => DEFAULT_HP, dummy_name => DEFAULT_HP },
      turn_order:   turn_order,
      current_turn: current,
      root_status:  reply_status,
      dummy:        true,
      difficulty:   diff
    }

    BattleState.set(battle_id, state)

    puts "[디버그] start_dummy_battle: battle_id=#{battle_id}"
    puts "[디버그] start_dummy_battle: current_turn=#{current} (String)"

    text = <<~TXT.strip
      ∴ 허수아비 전투 개시 (난이도: #{diff})!
      - 참가자: @#{user_id} vs #{dummy_name}
      - 시작 HP: #{DEFAULT_HP} / #{DEFAULT_HP}

      현재 턴: @#{current}
      행동: [공격] / [방어] / [도주]
    TXT

    @mastodon_client.reply_with_mentions(reply_status, text, [user_id])
  end

  # =============================
  #  공격
  # =============================
  def attack(user_id, target_id = nil)
    puts "[디버그] attack 호출: user_id='#{user_id}' (String)"

    battle_id, state = find_battle_state_for(user_id)

    puts "[디버그] state 존재: #{!state.nil?}"
    return unless state

    puts "[디버그] state[:type]=#{state[:type]}"
    puts "[디버그] current_turn='#{state[:current_turn]}' (String)"
    puts "[디버그] 일치 여부: #{state[:current_turn] == user_id}"
    puts "[디버그] 일치 여부(to_s): #{state[:current_turn].to_s == user_id.to_s}"

    # 턴이 아니면 무시
    return unless state[:current_turn].to_s == user_id.to_s

    opponent = pick_opponent(state, user_id, target_id)
    return unless opponent

    atk_roll = roll_d20
    dmg      = calc_damage(state, user_id, opponent, atk_roll)

    state[:hp][opponent] -= dmg
    state[:hp][opponent] = 0 if state[:hp][opponent] < 0

    root_status  = state[:root_status]
    participants = state[:players].reject { |p| dummy_name?(p) }

    text = build_attack_text(user_id, opponent, atk_roll, dmg, state)

    @mastodon_client.reply_with_mentions(root_status, text, participants)

    if state[:hp][opponent] <= 0
      finish_battle(battle_id, state, winner: user_id, loser: opponent)
    else
      BattleState.next_turn(battle_id)
      puts "[디버그] next_turn: current_turn=#{state[:current_turn]} (String)"
    end
  end

  # =============================
  #  방어 (타겟 지정)
  # =============================
  def defend_target(user_id, target_id)
    battle_id, state = find_battle_state_for(user_id)
    return unless state

    return unless state[:current_turn].to_s == user_id.to_s

    target = pick_opponent(state, user_id, target_id) || user_id

    root_status  = state[:root_status]
    participants = state[:players].reject { |p| dummy_name?(p) }

    text = <<~TXT.strip
      @#{user_id} 가(이) @#{target} 를 보호하기 위해 방어 태세를 취합니다.
      이번 턴 동안 방어 효과가 적용됩니다. (연출용)
    TXT

    @mastodon_client.reply_with_mentions(root_status, text, participants)

    BattleState.next_turn(battle_id)
    puts "[디버그] defend_target: next_turn=#{state[:current_turn]} (String)"
  end

  # =============================
  #  방어 (자신)
  # =============================
  def defend(user_id)
    battle_id, state = find_battle_state_for(user_id)
    return unless state
    return unless state[:current_turn].to_s == user_id.to_s

    root_status  = state[:root_status]
    participants = state[:players].reject { |p| dummy_name?(p) }

    text = <<~TXT.strip
      @#{user_id} 가(이) 몸을 낮추며 방어 태세를 취합니다.
      이번 턴에는 피해를 줄이기 위한 행동을 합니다. (연출용)
    TXT

    @mastodon_client.reply_with_mentions(root_status, text, participants)

    BattleState.next_turn(battle_id)
    puts "[디버그] defend: next_turn=#{state[:current_turn]} (String)"
  end

  # =============================
  #  반격
  # =============================
  def counter(user_id)
    battle_id, state = find_battle_state_for(user_id)
    return unless state
    return unless state[:current_turn].to_s == user_id.to_s

    opponent = (state[:players] - [user_id]).first
    root_status  = state[:root_status]
    participants = state[:players].reject { |p| dummy_name?(p) }

    atk_roll = roll_d20
    dmg      = (atk_roll / 2.0).ceil

    state[:hp][opponent] -= dmg
    state[:hp][opponent] = 0 if state[:hp][opponent] < 0

    text = <<~TXT.strip
      @#{user_id} 가(이) 빈틈을 노려 @#{opponent} 에게 반격합니다!
      - 주사위: d20 = #{atk_roll}
      - 피해: #{dmg}

      HP 현황:
      #{hp_status_line(state)}
    TXT

    @mastodon_client.reply_with_mentions(root_status, text, participants)

    if state[:hp][opponent] <= 0
      finish_battle(battle_id, state, winner: user_id, loser: opponent)
    else
      BattleState.next_turn(battle_id)
      puts "[디버그] counter: next_turn=#{state[:current_turn]} (String)"
    end
  end

  # =============================
  #  도주
  # =============================
  def flee(user_id)
    battle_id, state = find_battle_state_for(user_id)
    return unless state

    opponent = (state[:players] - [user_id]).first
    root_status  = state[:root_status]
    participants = state[:players].reject { |p| dummy_name?(p) }

    text = <<~TXT.strip
      @#{user_id} 가(이) 전투에서 도주했습니다.
      승자: @#{opponent}
    TXT

    @mastodon_client.reply_with_mentions(root_status, text, participants)

    finish_battle(battle_id, state, winner: opponent, loser: user_id)
  end

  private

  # =============================
  #  유틸
  # =============================

  def build_battle_id(*players)
    players.map { |p| p.to_s.downcase.gsub(/\s+/, '_') }.join('_vs_')
  end

  def find_battle_state_for(user_id)
    battle_id = BattleState.find_by_player(user_id)
    return [nil, nil] unless battle_id

    state = BattleState.get(battle_id)
    [battle_id, state]
  end

  def roll_d20
    rand(1..20)
  end

  def calc_damage(state, attacker, defender, roll)
    base = 10
    # 나중에 sheet_manager 연동해서 스탯 반영 가능
    (base + roll / 2.0).floor
  end

  def pick_opponent(state, user_id, target_id)
    players = state[:players]

    if target_id
      found = players.find { |p| p.to_s.downcase == target_id.to_s.downcase }
      return found if found
    end

    (players - [user_id]).first
  end

  def dummy_name?(name)
    name.to_s.start_with?("허수아비")
  end

  def hp_status_line(state)
    state[:players].map { |p| "@#{p}: #{state[:hp][p]} HP" }.join(" / ")
  end

  def finish_battle(battle_id, state, winner:, loser:)
    root_status  = state[:root_status]
    participants = state[:players].reject { |p| dummy_name?(p) }

    text = <<~TXT.strip
      ∴ 전투 종료!
      승자: @#{winner}
      패자: @#{loser}

      최종 HP:
      #{hp_status_line(state)}
    TXT

    @mastodon_client.reply_with_mentions(root_status, text, participants)
    BattleState.clear(battle_id)
  end
end
