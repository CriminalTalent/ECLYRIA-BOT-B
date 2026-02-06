# command_parser.rb
# 이모지 제거 버전

require_relative 'commands/battle_command'
require_relative 'commands/potion_command'

class CommandParser
  # GM 계정 목록 (관리자 권한)
  GM_ACCOUNTS = ['LIBRE', 'admin', 'gm', 'master'].freeze

  def initialize(mastodon_client, sheet_manager)
    @client = mastodon_client
    @sheet_manager = sheet_manager
    
    # 명령어 핸들러 초기화
    @battle_command = BattleCommand.new(@client, @sheet_manager)
    @potion_command = PotionCommand.new(@client, @sheet_manager)
    
    puts "[CommandParser] 초기화 완료"
  end

  def parse_and_execute(content, status, sender_id)
    # HTML 태그 제거 및 정리
    clean_content = content.gsub(/<[^>]*>/, '').strip
    
    # 봇 멘션 제거 (@battle 등)
    clean_content = clean_content.gsub(/@\w+\s*/, '').strip
    
    puts "[CommandParser] 처리: #{sender_id} - #{clean_content[0..50]}"
    
    begin
      # 전투 관련 명령어
      if handle_battle_commands(clean_content, status, sender_id)
        return
      end
      
      # 물약 관련 명령어  
      if handle_potion_commands(clean_content, status, sender_id)
        return
      end
      
      # 전투 액션 명령어
      if handle_battle_actions(clean_content, status, sender_id)
        return
      end
      
      # 관리자 명령어
      if handle_admin_commands(clean_content, status, sender_id)
        return
      end
      
      # 도움말
      if handle_help_commands(clean_content, status, sender_id)
        return
      end
      
      # 인식되지 않은 명령어
      puts "[CommandParser] 인식되지 않은 명령어: #{clean_content}"
      
    rescue => e
      puts "[CommandParser] 명령어 처리 오류: #{e.message}"
      puts e.backtrace[0..5]
      @client.reply(status, "@#{sender_id} 명령어 처리 중 오류가 발생했습니다.")
    end
  end

  private

  def handle_battle_commands(content, status, sender_id)
    # 1:1 전투 개시
    if content =~ /\[전투개시\/(@?\w+)\]/i
      opponent_id = $1.gsub('@', '').strip
      
      if opponent_id == sender_id
        @client.reply(status, "@#{sender_id} 자신과는 전투할 수 없습니다!")
        return true
      end
      
      @battle_command.start_1v1(sender_id, opponent_id, status)
      return true
    end

    # 2:2 팀전투 개시
    if content =~ /\[전투개시\/((?:@?\w+\/){3}@?\w+)\]/i ||
       content =~ /\[팀전투\/((?:@?\w+\/){3}@?\w+)\]/i
      participants_text = $1
      participants = participants_text.split('/').map { |p| p.gsub('@', '').strip }.reject(&:empty?)
      
      if participants.length != 4
        @client.reply(status, "@#{sender_id} 팀전투는 정확히 4명이 필요합니다.")
        return true
      end
      
      unless GM_ACCOUNTS.include?(sender_id) || participants.include?(sender_id)
        @client.reply(status, "@#{sender_id} 본인이 참가자에 포함되거나 GM이어야 합니다.")
        return true
      end
      
      @battle_command.start_2v2(participants[0], participants[1], participants[2], participants[3], status)
      return true
    end

    # 4:4 대규모전투 개시
    if content =~ /\[대규모전투\/((?:@?\w+\/){7}@?\w+)\]/i
      participants_text = $1
      participants = participants_text.split('/').map { |p| p.gsub('@', '').strip }.reject(&:empty?)
      
      if participants.length != 8
        @client.reply(status, "@#{sender_id} 대규모전투는 정확히 8명이 필요합니다.")
        return true
      end
      
      unless GM_ACCOUNTS.include?(sender_id) || participants.include?(sender_id)
        @client.reply(status, "@#{sender_id} 본인이 참가자에 포함되거나 GM이어야 합니다.")
        return true
      end
      
      @battle_command.start_4v4(participants[0], participants[1], participants[2], participants[3],
                                participants[4], participants[5], participants[6], participants[7], status)
      return true
    end


    false
  end

  def handle_battle_actions(content, status, sender_id)
    # 공격
    if content =~ /\[공격(?:\/(@?\w+))?\]/i
      target = $1 ? $1.gsub('@', '').strip : nil
      @battle_command.attack(sender_id, target, status)
      return true
    end

    # 방어
    if content =~ /\[방어(?:\/(@?\w+))?\]/i
      target = $1 ? $1.gsub('@', '').strip : nil
      @battle_command.defend(sender_id, target, status)
      return true
    end

    # 반격
    if content =~ /\[반격\]/i
      @battle_command.counter(sender_id, status)
      return true
    end

    # 물약사용 (전투 중)
    if content =~ /\[물약사용(?:\/(소형|중형|대형))?(?:\/(@?\w+))?\]/i
      potion_size = $1 || "소형"
      target = $2 ? $2.gsub('@', '').strip : nil
      @battle_command.use_potion(sender_id, potion_size, target, status)
      return true
    end

    # 도주
    if content =~ /\[도주\]/i
      # TODO: 도주 기능 구현 필요
      @client.reply(status, "@#{sender_id} 도주 기능은 아직 구현되지 않았습니다.")
      return true
    end

    false
  end

  def handle_potion_commands(content, status, sender_id)
    # 평상시 물약 사용
    if content =~ /\[물약\s*(소형|중형|대형)?\]/i
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
      @client.reply(status, "@#{sender_id}\n#{battle_list}")
      return true
    end

    # 전투 강제 종료
    if content =~ /\[전투종료\s+(\w+)\]/i
      battle_id = $1
      if BattleState.force_end_battle(battle_id, "GM 강제 종료")
        @client.reply(status, "@#{sender_id} 전투 #{battle_id}를 강제 종료했습니다.")
      else
        @client.reply(status, "@#{sender_id} 전투 #{battle_id}를 찾을 수 없습니다.")
      end
      return true
    end

    # 사용자 전투 강제 종료
    if content =~ /\[사용자전투종료\s+(@?\w+)\]/i
      target_user = $1.gsub('@', '').strip
      ended_battles = BattleState.force_end_user_battles(target_user, "GM 강제 종료")
      if ended_battles.any?
        @client.reply(status, "@#{sender_id} #{target_user}의 전투 #{ended_battles.size}개를 강제 종료했습니다.")
      else
        @client.reply(status, "@#{sender_id} #{target_user}의 진행 중인 전투가 없습니다.")
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
      
      @client.reply(status, message)
      return true
    end

    # 시간 초과 테스트
    if content =~ /\[시간초과테스트\s+(\w+)\]/i
      battle_id = $1
      if BattleState.force_timeout_battle(battle_id)
        @client.reply(status, "@#{sender_id} 전투 #{battle_id}의 시간을 강제로 초과시켰습니다.")
      else
        @client.reply(status, "@#{sender_id} 전투 #{battle_id}를 찾을 수 없습니다.")
      end
      return true
    end

    false
  end

  def handle_help_commands(content, status, sender_id)
    if content =~ /\[도움말\]/i || content =~ /\[명령어\]/i || content =~ /\[help\]/i
      help_message = <<~HELP
        @#{sender_id}
        ━━━━━━━━━━━━━━━━━━
        전투봇 명령어 도움말
        ━━━━━━━━━━━━━━━━━━
        
        전투 시작:
        [전투개시/@상대방] - 1:1 전투
        [전투개시/@팀원/@적1/@적2] - 2:2 전투  
        [대규모전투/@참가자7명] - 4:4 전투
        [허수아비 상/중/하] - 연습 전투
        
        전투 액션:
        [공격] 또는 [공격/@타겟] - 공격
        [방어] 또는 [방어/@타겟] - 방어
        [반격] - 반격 태세
        [물약사용] 또는 [물약사용/크기/@타겟]
        [도주] - 전투 도주
        
        물약 사용:
        [물약 소형/중형/대형] - 평상시 회복
        
        시간 제한:
        • 1인당 4분 제한 (초과시 자동 방어)
        • 전체 전투 1시간 제한
        • 1시간 후 체력 총합으로 승부
        
        ━━━━━━━━━━━━━━━━━━
      HELP
      
      @client.reply(status, help_message.strip)
      return true
    end

    false
  end
end
