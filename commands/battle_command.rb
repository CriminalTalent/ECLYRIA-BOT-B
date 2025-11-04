# commands/battle_command.rb
require_relative '../core/battle_engine'
require_relative '../core/battle_state'

class BattleCommand
  ADMIN_IDS = ["@ellis@remember.elbarand.pics", "@professor@remember.elbarand.pics"]

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
    # 전투 중단 명령
    if text.match(/\[전투중단\]/i)
      unless ADMIN_IDS.include?(user_id)
        @mastodon_client.reply(reply_id, "전투 중단 권한이 없습니다.", visibility: 'direct')
        return
      end
      if BattleState.active?
        snapshot = BattleState.current_snapshot
        BattleState.reset!
        summary_text = summarize_battle_result(snapshot, "총괄계 명령으로 전투가 강제 종료되었습니다.")
        @mastodon_client.reply(reply_id, summary_text, visibility: 'public')
        puts "[총괄계] #{user_id}가 전투를 중단함"
      else
        @mastodon_client.reply(reply_id, "현재 진행 중인 전투가 없습니다.", visibility: 'direct')
      end
      return
    end

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

    # HP 상태 표시
    battle_info = BattleState.current_snapshot
    if battle_info && battle_info["players"]
      status_lines = battle_info["players"].map do |p|
        "#{p['name']} | HP #{p['hp']} / #{p['max_hp']}"
      end
      @mastodon_client.reply(reply_id, status_lines.join("\n"), visibility: 'unlisted')
    end

    # 전투 종료 감지
    if battle_info && battle_info["players"].any? { |p| p["hp"].to_i <= 0 }
      summary_text = summarize_battle_result(battle_info)
      BattleState.reset!
      @mastodon_client.reply(reply_id, summary_text, visibility: 'unlisted')
      return
    end

    # 다음 턴 안내
    next_turn_user = BattleState.current_turn_user
    if next_turn_user == user_id
      guide = "당신의 턴입니다. 가능한 명령: [공격/물리], [공격/마법], [방어], [도망]"
    else
      guide = "상대의 턴입니다. 잠시 기다리세요."
    end

    @mastodon_client.reply(reply_id, guide, visibility: 'unlisted')
  rescue => e
    puts "[에러] 전투 처리 중 오류: #{e.message}"
    puts e.backtrace.first(5)
    @mastodon_client.reply(reply_id, "전투 처리 중 오류가 발생했습니다: #{e.message}", visibility: 'direct')
  end

  private

  # 전투 종료 요약 출력
  def summarize_battle_result(snapshot, reason = nil)
    lines = []
    lines << (reason || "전투가 종료되었습니다.")
    lines << ""
    snapshot["players"].each do |p|
      lines << "#{p['name']} | 최종 HP: #{p['hp']} / #{p['max_hp']}"
    end

    alive = snapshot["players"].select { |p| p["hp"].to_i > 0 }
    if alive.size == 1
      winner = alive.first["name"]
      lines << ""
      lines << "승자: #{winner}"
    elsif alive.empty?
      lines << ""
      lines << "모든 전투자가 쓰러졌습니다. 무승부로 처리됩니다."
    else
      lines << ""
      lines << "전투가 조기 종료되었습니다."
    end

    lines.join("\n")
  end
end
