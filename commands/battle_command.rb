# commands/battle_command.rb
require_relative '../core/battle_engine'
require_relative '../core/battle_state'

class BattleCommand
  def initialize(mastodon_client, sheet_manager)
    @mastodon_client = mastodon_client
    @sheet_manager = sheet_manager
    @battle_engine = BattleEngine.new(mastodon_client, sheet_manager)
  end

  # 전투 개시
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
      @mastodon_client.reply(
        reply_id,
        "전투 형식이 올바르지 않습니다.\n" \
        "1:1 전투: [전투개시/@상대방]\n" \
        "2:2 전투: [전투개시/@우리팀/@상대방1/@상대방2]",
        visibility: 'public'
      )
    end
  end

  # 허수아비 전투 (연습)
  def start_dummy_battle(text, user_id, reply_id)
    if BattleState.active?
      @mastodon_client.reply(reply_id, "이미 진행 중인 전투가 있습니다.", visibility: 'public')
      return
    end

    match = text.match(/\[허수아비\s+(상|중|하)\]/i)
    difficulty = match[1]
    @battle_engine.start_dummy_battle(user_id, difficulty, reply_id)
  end

  # 전투 중 행동 처리
  def handle_action(text, user_id, reply_id)
    unless BattleState.active?
      @mastodon_client.reply(reply_id, "진행 중인 전투가 없습니다.", visibility: 'direct')
      return
    end

    action = nil
    if text.match(/\[공격\]/i)
      action = "공격"
      result = @battle_engine.attack(user_id)
    elsif text.match(/\[방어\]/i)
      action = "방어"
      result = @battle_engine.defend(user_id)
    elsif text.match(/\[반격\]/i)
      action = "반격"
      result = @battle_engine.counter(user_id)
    elsif text.match(/\[도주\]/i)
      action = "도주"
      result = @battle_engine.flee(user_id)
    else
      @mastodon_client.reply(reply_id, "알 수 없는 명령입니다. [공격], [방어], [반격], [도주] 중 하나를 선택하세요.", visibility: 'direct')
      return
    end

    # 전투 로그 출력
    @mastodon_client.reply(reply_id, result, visibility: 'unlisted')

    # 다음 턴 안내
    next_turn_user = BattleState.current_turn_user
    if next_turn_user == user_id
      guide = "당신의 턴입니다. 가능한 명령: [공격/물리], [공격/마법], [방어], [도주]"
    else
      guide = "상대의 턴입니다. 잠시 기다리세요."
    end

    @mastodon_client.reply(reply_id, guide, visibility: 'unlisted')
  rescue => e
    puts "[에러] 전투 처리 중 오류: #{e.message}"
    puts e.backtrace.first(5)
    @mastodon_client.reply(reply_id, "전투 처리 중 오류가 발생했습니다: #{e.message}", visibility: 'direct')
  end
end
