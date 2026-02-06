# command_parser.rb
# 모든 기능 포함 완전 버전 + 태그/리모트 계정 처리 개선 + 1:1 타겟 액션 제한
# + Hash(status) / 객체(status) 모두 지원
# + 무응답 방지(알 수 없는 명령어/에러 시에도 반드시 답글 시도)
# + @Battle 멘션 제거 강화(여러 형태 대응)
# + 상태/계정 접근을 dig로 통일

require_relative 'commands/battle_command'
require_relative 'commands/potion_command'

class CommandParser
  # GM 계정 목록 (관리자 권한)
  GM_ACCOUNTS = ['LIBRE', 'admin', 'gm', 'master'].freeze

  # user 또는 user@domain 허용 (멘션 앞에 @가 붙어도 됨)
  USER_TOKEN = /@?[A-Za-z0-9_]+(?:@[A-Za-z0-9\.\-]+)?/

  # 봇 계정명(멘션 제거용) - 환경에 맞게 바꾸고 싶으면 여기만
  BOT_NAME = 'Battle'.freeze

  def initialize(mastodon_client, sheet_manager)
    @client = mastodon_client
    @sheet_manager = sheet_manager

    # 명령어 핸들러 초기화
    @battle_command = BattleCommand.new(@client, @sheet_manager)
    @potion_command = PotionCommand.new(@client, @sheet_manager)

    puts "[CommandParser] 초기화 완료"
  end

  def parse_and_execute(content, status, sender_id)
    # 0) content 정규화 (여기서 HTML 제거/멘션 복원/제로폭 제거까지 다 처리)
    clean_content = normalize_content(content)

    puts "[CommandParser] 원본: #{content.to_s[0..100]}"
    puts "[CommandParser] 정리된 내용: #{clean_content.to_s[0..100]}"
    puts "[CommandParser] 처리: #{sender_id} - #{clean_content}"

    begin
      # 체력 확인 명령어 (우선 처리)
      return true if handle_hp_check_commands(clean_content, status, sender_id)

      # 전투 중단 명령어
      return true if handle_battle_stop_commands(clean_content, status, sender_id)

      # 전투 관련 명령어
      return true if handle_battle_commands(clean_content, status, sender_id)

      # 물약 관련 명령어
      return true if handle_potion_commands(clean_content, status, sender_id)

      # 전투 액션 명령어
      return true if handle_battle_actions(clean_content, status, sender_id)

      # 관리자 명령어
      return true if handle_admin_commands(clean_content, status, sender_id)

      # 인식되지 않은 명령어: 무응답 방지
      puts "[CommandParser] 인식되지 않은 명령어: #{clean_content}"
      safe_reply(
        status,
        "@#{sender_id} 명령어를 이해하지 못했어요.\n" \
        "예시: [HP], [전투/@상대], [팀전투/@A/@B/@C/@D], [대규모전투/@A/@B/@C/@D/@E/@F/@G/@H], [공격], [방어], [반격], [물약사용/소형]"
      )
      true
    rescue => e
      puts "[CommandParser] 명령어 처리 오류: #{e.message}"
      puts e.backtrace[0..8]
      safe_reply(status, "@#{sender_id} 명령어 처리 중 오류가 발생했습니다.")
      true
    end
  end

  private

  # -----------------------------
  # 공통 유틸 (Hash/객체 대응)
  # -----------------------------

  def status_id_of(status)
    if status.is_a?(Hash)
      (status['id'] || status[:id]).to_s
    elsif status.respond_to?(:id)
      status.id.to_s
    else
      status.to_s
    end
  end

  def status_account_of(status)
    if status.is_a?(Hash)
      status['account'] || status[:account]
    elsif status.respond_to?(:account)
      status.account
    else
      nil
    end
  end

  def account_acct_of(account)
    if account.is_a?(Hash)
      (account['acct'] || account[:acct]).to_s
    elsif account.respond_to?(:acct)
      account.acct.to_s
    else
      ""
    end
  end

  # reply가 내부적으로 status 객체를 가정하다가 터질 수 있어서,
  # 여기서는 "시도하고 실패해도 로그만 남기고 죽지 않게" 한다.
  def safe_reply(status, message)
    @client.reply(status, message)
  rescue => e
    puts "[CommandParser] reply 실패: #{e.message} (status_id=#{status_id_of(status)})"
    puts e.backtrace[0..5]
    false
  end

  def normalize_content(content)
    s = content.to_s

    # HTML 태그 제거 및 정리
    s = s.gsub(/<[^>]*>/, '').strip

    # 멘션 깨짐 복원: "@ Battle" -> "@Battle"
    s = s.gsub(/@\s+/, '@')

    # 제로폭/유니코드 BOM 등 제거(정규식 매칭 실패 원인)
    s = s.gsub(/\u200B|\uFEFF/, '')

    # 봇 멘션만 제거:
    # - 맨 앞에 붙은 "@Battle", "@battle@domain" 등 제거
    # - 여러 멘션이 연속인 경우도 제거
    s = s.sub(/\A@#{Regexp.escape(BOT_NAME)}(?:@[A-Za-z0-9\.\-]+)?\b\s*/i, '').strip
    s
  end

  def normalize_user_token(token)
    token.to_s.strip.sub(/\A@/, '') # 맨 앞의 @만 제거 (도메인 @는 유지)
  end

  # ---- 전투 컨텍스트 판단 (1:1 vs 다인) ----
  def current_battle_participant_count(sender_id)
    return nil unless defined?(BattleState)
    battle = BattleState.find_by_participant(sender_id)
    return nil unless battle

    # 1) battle이 Hash 형태인 경우
    if battle.is_a?(Hash)
      participants = battle[:participants] || battle['participants'] ||
                     battle[:members] || battle['members']
      if participants.is_a?(Array)
        return participants.size
      end

      if battle[:battle_type] || battle['battle_type']
        t = (battle[:battle_type] || battle['battle_type']).to_s
        return 2 if t =~ /1v1|pvp|single/i
        return 4 if t =~ /2v2/i
        return 8 if t =~ /4v4|large/i
      end
    end

    # 2) battle이 객체 형태인 경우
    if battle.respond_to?(:participants)
      p = battle.participants
      return p.size if p.is_a?(Array)
    end
    if battle.respond_to?(:members)
      p = battle.members
      return p.size if p.is_a?(Array)
    end
    if battle.respond_to?(:participant_ids)
      p = battle.participant_ids
      return p.size if p.is_a?(Array)
    end
    if battle.respond_to?(:battle_type)
      t = battle.battle_type.to_s
      return 2 if t =~ /1v1|pvp|single/i
      return 4 if t =~ /2v2/i
      return 8 if t =~ /4v4|large/i
    end

    nil
  rescue => e
    puts "[CommandParser] 전투 컨텍스트 판정 실패: #{e.message}"
    nil
  end

  def one_vs_one_battle?(sender_id)
    cnt = current_battle_participant_count(sender_id)
    return false if cnt.nil? # 알 수 없으면 제한하지 않음(기존 동작 유지)
    cnt == 2
  end
  # ----------------------------------------

  # -----------------------------
  # 명령 처리
  # -----------------------------

  def handle_hp_check_commands(content, status, sender_id)
    return false unless content =~ /\[(체력|HP)\]/i

    user = @sheet_manager.find_user(sender_id)
    unless user
      safe_reply(status, "@#{sender_id} 사용자를 찾을 수 없습니다.")
      return true
    end

    current_hp = (user["HP"] || 0).to_i
    max_hp = 100 + ((user["체력"] || 10).to_i * 10)
    user_name = user["이름"] || sender_id

    hp_bar = generate_hp_bar(current_hp, max_hp)
    message = "@#{sender_id}\n#{user_name}의 체력:\n#{hp_bar}"
    safe_reply(status, message)
    true
  end

  def handle_battle_stop_commands(content, status, sender_id)
    # 1:1 전투 중단
    if content =~ /\[전투중단[\/\s]*(#{USER_TOKEN})[\/\s]*(#{USER_TOKEN})\]/i
      user1 = normalize_user_token($1)
      user2 = normalize_user_token($2)

      unless GM_ACCOUNTS.include?(sender_id)
        safe_reply(status, "@#{sender_id} 전투 중단은 GM만 가능합니다.")
        return true
      end

      battle1 = BattleState.find_by_participant(user1)
      battle2 = BattleState.find_by_participant(user2)

      if battle1 && battle1 == battle2
        battle_id = BattleState.find_battle_id_by_participant(user1)
        if BattleState.force_end_battle(battle_id, "GM 전투 중단")
          safe_reply(status, "@#{sender_id} #{user1} vs #{user2} 전투를 중단했습니다.")
        else
          safe_reply(status, "@#{sender_id} 전투 중단에 실패했습니다.")
        end
      else
        safe_reply(status, "@#{sender_id} 해당 사용자들의 전투를 찾을 수 없습니다.")
      end
      return true
    end

    # 2:2/4:4 전투 중단
    if content =~ /\[전투중단[\/\s]*((?:#{USER_TOKEN}[\/\s]*){3,7}#{USER_TOKEN})\]/i
      participants_text = $1
      participants = participants_text
        .split(/[\/\s]+/)
        .map { |p| normalize_user_token(p) }
        .reject(&:empty?)

      unless GM_ACCOUNTS.include?(sender_id)
        safe_reply(status, "@#{sender_id} 전투 중단은 GM만 가능합니다.")
        return true
      end

      battle = BattleState.find_by_participant(participants[0])
      if battle
        battle_id = BattleState.find_battle_id_by_participant(participants[0])
        if BattleState.force_end_battle(battle_id, "GM 전투 중단")
          safe_reply(status, "@#{sender_id} #{participants.join(' vs ')} 전투를 중단했습니다.")
        else
          safe_reply(status, "@#{sender_id} 전투 중단에 실패했습니다.")
        end
      else
        safe_reply(status, "@#{sender_id} 해당 참가자들의 전투를 찾을 수 없습니다.")
      end
      return true
    end

    false
  end

  def handle_battle_commands(content, status, sender_id)
    puts "[CommandParser] 전투 명령어 체크: #{content}"

    # ⚠️ 주의: 정규식 순서가 매우 중요
    # - GM형([전투/@A/@B])이 단축형([전투/@상대])을 잡아먹지 않도록
    # - GM형(2명) 먼저, 단축형(1명) 다음이 더 안정적임
    #
    # 하지만 단축형은 1명만 있을 때, GM형은 2명일 때만 매칭되도록 명확히 해두면 순서 영향이 줄어듦.

    # GM 1:1 전투 - [전투/@A/@B]
    if content =~ /\[전투[\/\s]*(#{USER_TOKEN})[\/\s]*(#{USER_TOKEN})\]/i
      user1 = normalize_user_token($1)
      user2 = normalize_user_token($2)
      puts "[CommandParser] GM 1v1 전투: #{user1} vs #{user2}"

      unless GM_ACCOUNTS.include?(sender_id)
        safe_reply(status, "@#{sender_id} GM만 다른 사용자들끼리 전투를 시작할 수 있습니다.")
        return true
      end

      if user1 == user2
        safe_reply(status, "@#{sender_id} 같은 사용자끼리는 전투할 수 없습니다!")
        return true
      end

      @battle_command.start_1v1(user1, user2, status)
      return true
    end

    # 1:1 전투 개시 - [전투/@상대]
    if content =~ /\[전투[\/\s]*(#{USER_TOKEN})\]/i
      opponent_id = normalize_user_token($1)
      puts "[CommandParser] 1v1 전투 대상: #{opponent_id}"

      if opponent_id.empty?
        safe_reply(status, "@#{sender_id} 전투 상대를 지정해주세요. 예: [전투/@상대방]")
        return true
      end

      if opponent_id == sender_id
        safe_reply(status, "@#{sender_id} 자신과는 전투할 수 없습니다!")
        return true
      end

      @battle_command.start_1v1(sender_id, opponent_id, status)
      return true
    end

    # 2:2 팀전투 개시
    if content =~ /\[팀전투[\/\s]*((?:#{USER_TOKEN}[\/\s]*){3}#{USER_TOKEN})\]/i
      participants_text = $1
      puts "[CommandParser] 팀전투 참가자 텍스트: #{participants_text}"

      participants = participants_text
        .split(/[\/\s]+/)
        .map { |p| normalize_user_token(p) }
        .reject(&:empty?)

      puts "[CommandParser] 팀전투 참가자 목록: #{participants.inspect}"

      if participants.length != 4
        safe_reply(status, "@#{sender_id} 팀전투는 정확히 4명이 필요합니다. 현재: #{participants.length}명")
        return true
      end

      unless GM_ACCOUNTS.include?(sender_id) || participants.include?(sender_id)
        safe_reply(status, "@#{sender_id} 본인이 참가자에 포함되거나 GM이어야 합니다.")
        return true
      end

      @battle_command.start_2v2(participants[0], participants[1], participants[2], participants[3], status)
      return true
    end

    # 4:4 대규모전투 개시
    if content =~ /\[대규모전투[\/\s]*((?:#{USER_TOKEN}[\/\s]*){7}#{USER_TOKEN})\]/i
      participants_text = $1
      participants = participants_text
        .split(/[\/\s]+/)
        .map { |p| normalize_user_token(p) }
        .reject(&:empty?)

      if participants.length != 8
        safe_reply(status, "@#{sender_id} 대규모전투는 정확히 8명이 필요합니다.")
        return true
      end

      unless GM_ACCOUNTS.include?(sender_id) || participants.include?(sender_id)
        safe_reply(status, "@#{sender_id} 본인이 참가자에 포함되거나 GM이어야 합니다.")
        return true
      end

      @battle_command.start_4v4(
        participants[0], participants[1], participants[2], participants[3],
        participants[4], participants[5], participants[6], participants[7],
        status
      )
      return true
    end

    # 허수아비 전투
    if content =~ /\[허수아비\s+(상|중|하)\]/i
      difficulty = $1
      safe_reply(status, "@#{sender_id} 허수아비 전투는 아직 구현되지 않았습니다.")
      return true
    end

    false
  end

  def handle_battle_actions(content, status, sender_id)
    # 1:1 전투 여부(판단 불가면 nil -> 제한하지 않음)
    is_1v1 = one_vs_one_battle?(sender_id)

    # 공격: [공격] 또는 [공격/@타겟]
    if content =~ /\[공격(?:[\/\s]*(#{USER_TOKEN}))?\]/i
      raw_target = $1
      target = raw_target ? normalize_user_token(raw_target) : nil

      # 1:1이면 타겟 지정 금지
      if is_1v1 && target
        safe_reply(
          status,
          "@#{sender_id} 1:1 전투에서는 타겟 지정이 없습니다.\n다음 행동: [공격] [방어] [반격] [물약사용/크기]"
        )
        return true
      end

      @battle_command.attack(sender_id, target, status)
      return true
    end

    # 방어: [방어] 또는 [방어/@타겟]
    if content =~ /\[방어(?:[\/\s]*(#{USER_TOKEN}))?\]/i
      raw_target = $1
      target = raw_target ? normalize_user_token(raw_target) : nil

      if is_1v1 && target
        safe_reply(
          status,
          "@#{sender_id} 1:1 전투에서는 타겟 지정이 없습니다.\n다음 행동: [공격] [방어] [반격] [물약사용/크기]"
        )
        return true
      end

      @battle_command.defend(sender_id, target, status)
      return true
    end

    # 반격: [반격]
    if content =~ /\[반격\]/i
      @battle_command.counter(sender_id, status)
      return true
    end

    # 물약사용(전투 중):
    # 1:1 -> [물약사용/크기]만 허용 (타겟 금지)
    # 다인 -> [물약사용/크기/@타겟] 허용
    if content =~ /\[물약사용(?:[\/\s]*(소형|중형|대형))?(?:[\/\s]*(#{USER_TOKEN}))?\]/i
      potion_size = $1 || "소형"
      raw_target = $2
      target = raw_target ? normalize_user_token(raw_target) : nil

      if is_1v1 && target
        safe_reply(
          status,
          "@#{sender_id} 1:1 전투에서는 타겟 지정 물약을 사용할 수 없습니다.\n다음 행동: [공격] [방어] [반격] [물약사용/크기]"
        )
        return true
      end

      @battle_command.use_potion(sender_id, potion_size, target, status)
      return true
    end

    false
  end

  def handle_potion_commands(content, status, sender_id)
    # 평상시 물약 사용 - [물약/소형] 형식
    if content =~ /\[물약[\/\s]*(소형|중형|대형)?\]/i
      potion_size = $1 || "소형"
      @potion_command.use_potion_casual(sender_id, potion_size, status)
      return true
    end

    false
  end

  def handle_admin_commands(content, status, sender_id)
    return false unless GM_ACCOUNTS.include?(sender_id)

    # 전투 목록 확인
    if content =~ /\[전투목록\]/i || content =~ /\[전투상태\]/i
      battle_list = BattleState.list_active_battles
      safe_reply(status, "@#{sender_id}\n#{battle_list}")
      return true
    end

    # 전투 강제 종료
    if content =~ /\[전투종료\s+(\w+)\]/i
      battle_id = $1
      if BattleState.force_end_battle(battle_id, "GM 강제 종료")
        safe_reply(status, "@#{sender_id} 전투 #{battle_id}를 강제 종료했습니다.")
      else
        safe_reply(status, "@#{sender_id} 전투 #{battle_id}를 찾을 수 없습니다.")
      end
      return true
    end

    # 사용자 전투 강제 종료
    if content =~ /\[사용자전투종료\s+(#{USER_TOKEN})\]/i
      target_user = normalize_user_token($1)
      ended_battles = BattleState.force_end_user_battles(target_user, "GM 강제 종료")
      if ended_battles.any?
        safe_reply(status, "@#{sender_id} #{target_user}의 전투 #{ended_battles.size}개를 강제 종료했습니다.")
      else
        safe_reply(status, "@#{sender_id} #{target_user}의 진행 중인 전투가 없습니다.")
      end
      return true
    end

    # 전투 통계
    if content =~ /\[전투통계\]/i
      stats = BattleState.get_battle_status_summary
      message = "@#{sender_id}\n━━━━━━━━━━━━━━━━━━\n전투 시스템 통계\n━━━━━━━━━━━━━━━━━━\n"
      message += "1:1 전투: #{stats[:pvp][:count]}개 (평균 #{stats[:pvp][:avg_duration] / 60}분)\n"
      message += "2:2 전투: #{stats[:team_2v2][:count]}개 (평균 #{stats[:team_2v2][:avg_duration] / 60}분)\n"
      message += "4:4 전투: #{stats[:team_4v4][:count]}개 (평균 #{stats[:team_4v4][:avg_duration] / 60}분)\n"
      message += "대기 중인 액션: #{stats[:waiting_actions]}개\n"
      message += "멈춘 전투: #{stats[:stuck_battles]}개\n"
      message += "━━━━━━━━━━━━━━━━━━"

      safe_reply(status, message)
      return true
    end

    # 시간 초과 테스트
    if content =~ /\[시간초과테스트\s+(\w+)\]/i
      battle_id = $1
      if BattleState.force_timeout_battle(battle_id)
        safe_reply(status, "@#{sender_id} 전투 #{battle_id}의 시간을 강제로 초과시켰습니다.")
      else
        safe_reply(status, "@#{sender_id} 전투 #{battle_id}를 찾을 수 없습니다.")
      end
      return true
    end

    false
  end

  def generate_hp_bar(current_hp, max_hp, bar_length = 10)
    return "█" * bar_length + " #{current_hp}/#{max_hp}" if current_hp >= max_hp
    return "░" * bar_length + " #{current_hp}/#{max_hp}" if current_hp <= 0 || max_hp <= 0

    filled_length = ((current_hp.to_f / max_hp.to_f) * bar_length).round
    empty_length = bar_length - filled_length

    "█" * filled_length + "░" * empty_length + " #{current_hp}/#{max_hp}"
  end
end
