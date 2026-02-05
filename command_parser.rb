require_relative 'commands/battle_command'
require_relative 'commands/potion_command'
require_relative 'commands/heal_command'
require_relative 'commands/hp_command'

# 전투 안내 메시지 헬퍼
module BattleMessages
  def self.get_1v1_options
    "[공격] [방어] [반격] [물약사용/크기]"
  end
  
  def self.get_multi_options
    "[공격/@타겟] [방어] [방어/@아군] [반격] [물약사용/크기/@아군]"
  end
end

class CommandParser
  GM_ACCOUNTS = ['Story', 'professor', 'Store', 'FortunaeFons'].freeze

  def initialize(mastodon_client, sheet_manager)
    @mastodon_client = mastodon_client
    @sheet_manager = sheet_manager
    @battle_command = BattleCommand.new(mastodon_client, sheet_manager)
    @potion_command = PotionCommand.new(mastodon_client, sheet_manager)
    @heal_command = HealCommand.new(mastodon_client, sheet_manager)
    @hp_command = HpCommand.new(mastodon_client, sheet_manager)
    puts "[파서] 초기화 완료"
  end

  def handle(status)
    content = status[:content]
    text = content.gsub(/<[^>]+>/, '').strip
    user_id = status[:account][:acct]
    parse(text, user_id, status)
  end

  def parse(text, user_id, reply_status)
    text = text.strip
    
    puts "[전투봇] 명령 수신: #{text} (from @#{user_id})"

    # ============================================
    # 우선순위 1: 물약 명령어 (가장 먼저 처리)
    # ============================================
    # [물약사용/크기] 또는 [물약사용/크기/@타겟]
    if text =~ /\[물약사용(?:\/(소형|중형|대형))?(?:\/(@?\w+))?\]/i
      potion_size = $1 # 크기 (소형/중형/대형)
      target = $2 ? $2.gsub('@', '').strip : nil
      
      handle_potion_command_v2(potion_size, user_id, target, reply_status)
      return
    end

    # ============================================
    # 우선순위 2: 반격 (물약 다음으로 처리)
    # ============================================
    if text =~ /\[반격\]/i
      @battle_command.counter(user_id, reply_status)
      return
    end

    # ============================================
    # 나머지 명령어들
    # ============================================

    # GM 전투 중단
    if text =~ /\[전투중단((?:\/@?\w+)+)\]/i
      unless GM_ACCOUNTS.include?(user_id)
        @mastodon_client.reply(reply_status, "GM 권한이 필요합니다.")
        return
      end
      
      participants_text = $1
      participants = participants_text.split('/').map { |p| p.gsub('@', '').strip }.reject(&:empty?)
      handle_gm_end_battle(user_id, participants, reply_status)
      return
    end

    # 체력 확인
    if text =~ /\[체력\]/i
      @hp_command.check_hp(user_id, reply_status)
      return
    end

    # 1:1 전투 개시
    # [전투/@A] 또는 [전투개시/@A]
    if text =~ /\[전투(?:개시)?\/(@?\w+)\]/i
      target = $1.gsub('@', '').strip
      
      if GM_ACCOUNTS.include?(user_id)
        @mastodon_client.reply(reply_status, "GM은 [전투/@A/@B] 형식으로 두 플레이어를 지정해야 합니다.")
        return
      end
      
      @battle_command.start_1v1(user_id, target, reply_status)
      return
    end

    # GM 1:1 전투 개시
    # [전투/@A/@B]
    if text =~ /\[전투\/(@?\w+)\/(@?\w+)\]/i
      unless GM_ACCOUNTS.include?(user_id)
        @mastodon_client.reply(reply_status, "일반 사용자는 [전투/@상대] 형식을 사용하세요.")
        return
      end
      
      player1 = $1.gsub('@', '').strip
      player2 = $2.gsub('@', '').strip
      @battle_command.start_1v1(player1, player2, reply_status)
      return
    end

    # 2:2 전투 개시
    # [팀전투/@A/@B/@C/@D]
    if text =~ /\[팀전투((?:\/@?\w+){4})\]/i
      participants_text = $1
      participants = participants_text.split('/').map { |p| p.gsub('@', '').strip }.reject(&:empty?)
      
      if participants.length != 4
        @mastodon_client.reply(reply_status, "팀전투는 정확히 4명이 필요합니다.")
        return
      end
      
      unless GM_ACCOUNTS.include?(user_id) || participants.include?(user_id)
        @mastodon_client.reply(reply_status, "본인이 참가자에 포함되거나 GM이어야 합니다.")
        return
      end
      
      @battle_command.start_2v2(participants[0], participants[1], participants[2], participants[3], reply_status)
      return
    end

    # 4:4 전투 개시
    # [대규모전투/@A/@B/@C/@D/@E/@F/@G/@H]
    if text =~ /\[대규모전투((?:\/@?\w+){8})\]/i
      participants_text = $1
      participants = participants_text.split('/').map { |p| p.gsub('@', '').strip }.reject(&:empty?)
      
      if participants.length != 8
        @mastodon_client.reply(reply_status, "대규모전투는 정확히 8명이 필요합니다.")
        return
      end
      
      unless GM_ACCOUNTS.include?(user_id) || participants.include?(user_id)
        @mastodon_client.reply(reply_status, "본인이 참가자에 포함되거나 GM이어야 합니다.")
        return
      end
      
      @battle_command.start_4v4(participants[0], participants[1], participants[2], participants[3],
                                participants[4], participants[5], participants[6], participants[7], reply_status)
      return
    end

    # 전투 행동 - 공격
    if text =~ /\[공격(?:\/(@?\w+))?\]/i
      target = $1 ? $1.gsub('@', '').strip : nil
      @battle_command.attack(user_id, target, reply_status)
      return
    end

    # 전투 행동 - 방어
    if text =~ /\[방어(?:\/(@?\w+))?\]/i
      target = $1 ? $1.gsub('@', '').strip : nil
      @battle_command.defend(user_id, target, reply_status)
      return
    end

    puts "[무시] 인식되지 않은 명령: #{text}"

  rescue => e
    puts "[에러] CommandParser 오류: #{e.message}"
    puts e.backtrace.first(5)
    @mastodon_client.reply(reply_status, "@#{user_id} 명령 처리 중 오류가 발생했습니다.")
  end

  private

  def handle_potion_command_v2(potion_size, user_id, target, reply_status)
    # 물약 크기 기본값 설정
    potion_type = potion_size || "소형"
    
    # 타겟이 있으면 아군에게, 없으면 본인에게
    if target && target != user_id
      # 타인에게 사용
      @potion_command.use_potion_for_target(user_id, reply_status, potion_type, target)
    else
      # 본인에게 사용
      @potion_command.use_potion(user_id, reply_status, potion_type)
    end
  end

  def handle_potion_command(text, user_id, reply_status)
    # 물약 타입 추출
    potion_type = nil
    if text =~ /소형/i
      potion_type = "소형"
    elsif text =~ /중형/i
      potion_type = "중형"
    elsif text =~ /대형/i
      potion_type = "대형"
    end

    # 대상 추출 (@유저명 패턴)
    target = nil
    if text =~ /@(\w+)/
      target = $1
    end

    # 물약 사용
    if target && target != user_id
      # 타인에게 사용
      @potion_command.use_potion_for_target(user_id, reply_status, potion_type, target)
    else
      # 본인에게 사용
      @potion_command.use_potion(user_id, reply_status, potion_type)
    end
  end

  def handle_gm_end_battle(gm_id, participants, reply_status)
    require_relative 'state/battle_state'
    
    # 참가자들이 포함된 전투 찾기
    battle_id = BattleState.find_battle_by_participants(participants)
    
    if battle_id
      battle = BattleState.get(battle_id)
      BattleState.clear(battle_id)
      
      msg = "@#{gm_id}님이 전투를 중단했습니다.\n"
      msg += "참가자: #{participants.map { |p| "@#{p}" }.join(', ')}"
      
      @mastodon_client.reply(reply_status, msg)
    else
      @mastodon_client.reply(reply_status, "해당 참가자들의 전투를 찾을 수 없습니다.")
    end
  end
end
