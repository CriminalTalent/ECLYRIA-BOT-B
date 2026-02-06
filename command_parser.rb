# command_parser.rb
# 모든 기능 포함 완전 버전

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
    
    # 봇 멘션만 제거 (@Battle, @battle 등) - 명령어 내의 @는 보존
    clean_content = clean_content.gsub(/@Battle\s*/i, '').strip
    
    puts "[CommandParser] 원본: #{content[0..100]}"
    puts "[CommandParser] 정리된 내용: #{clean_content[0..100]}"
    puts "[CommandParser] 처리: #{sender_id} - #{clean_content}"
    
    begin
      # 체력 확인 명령어 (우선 처리)
      if handle_hp_check_commands(clean_content, status, sender_id)
        return
      end
      
      # 전투 중단 명령어
      if handle_battle_stop_commands(clean_content, status, sender_id)
        return
      end
      
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
      
      # 인식되지 않은 명령어
      puts "[CommandParser] 인식되지 않은 명령어: #{clean_content}"
      
    rescue => e
      puts "[CommandParser] 명령어 처리 오류: #{e.message}"
      puts e.backtrace[0..5]
      @client.reply(status, "@#{sender_id} 명령어 처리 중 오류가 발생했습니다.")
    end
  end

  private

  def handle_hp_check_commands(content, status, sender_id)
    # 체력 확인
    if content =~ /\[(체력|HP)\]/i
      user = @sheet_manager.find_user(sender_id)
      unless user
        @client.reply(status, "@#{sender_id} 사용자를 찾을 수 없습니다.")
        return true
      end
      
      current_hp = (user["HP"] || 0).to_i
      max_hp = 100 + ((user["체력"] || 10).to_i * 10)
      user_name = user["이름"] || sender_id
      
      # 체력바 생성
      hp_bar = generate_hp_bar(current_hp, max_hp)
      
      message = "@#{sender_id}\n#{user_name}의 체력:\n#{hp_bar}"
      @client.reply(status, message)
      return true
    end
    
    false
  end

  def handle_battle_stop_commands(content, status, sender_id)
    # 1:1 전투 중단
    if content =~ /\[전투중단[\/\s]*(@?\w+)[\/\s]*(@?\w+)\]/i
      user1 = $1.gsub('@', '').strip
      user2 = $2.gsub('@', '').strip
      
      unless GM_ACCOUNTS.include?(sender_id)
        @client.reply(status, "@#{sender_id} 전투 중단은 GM만 가능합니다.")
        return true
      end
      
      # 해당 사용자들의 전투 찾기 및 중단
      battle1 = BattleState.find_by_participant(user1)
      battle2 = BattleState.find_by_participant(user2)
      
      if battle1 && battle1 == battle2
        battle_id = BattleState.find_battle_id_by_participant(user1)
        if BattleState.force_end_battle(battle_id, "GM 전투 중단")
          @client.reply(status, "@#{sender_id} #{user1} vs #{user2} 전투를 중단했습니다.")
        else
          @client.reply(status, "@#{sender_id} 전투 중단에 실패했습니다.")
        end
      else
        @client.reply(status, "@#{sender_id} 해당 사용자들의 전투를 찾을 수 없습니다.")
      end
      return true
    end
    
    # 2:2/4:4 전투 중단
    if content =~ /\[전투중단[\/\s]*((?:@?\w+[\/\s]*){3,7}@?\w+)\]/i
      participants_text = $1
      participants = participants_text.split(/[\/\s]+/).map { |p| p.gsub('@', '').strip }.reject(&:empty?)
      
      unless GM_ACCOUNTS.include?(sender_id)
        @client.reply(status, "@#{sender_id} 전투 중단은 GM만 가능합니다.")
        return true
      end
      
      # 첫 번째 참가자의 전투 찾기
      battle = BattleState.find_by_participant(participants[0])
      if battle
        battle_id = BattleState.find_battle_id_by_participant(participants[0])
        if BattleState.force_end_battle(battle_id, "GM 전투 중단")
          @client.reply(status, "@#{sender_id} #{participants.join(' vs ')} 전투를 중단했습니다.")
        else
          @client.reply(status, "@#{sender_id} 전투 중단에 실패했습니다.")
        end
      else
        @client.reply(status, "@#{sender_id} 해당 참가자들의 전투를 찾을 수 없습니다.")
      end
      return true
    end
    
    false
  end

  def handle_battle_commands(content, status, sender_id)
    puts "[CommandParser] 전투 명령어 체크: #{content}"
    
    # 1:1 전투 개시 - [전투/@상대] 형식
    if content =~ /\[전투[\/\s]*(@?\w+)\]/i
      opponent_id = $1.gsub('@', '').strip
      puts "[CommandParser] 1v1 전투 대상: #{opponent_id}"
      
      if opponent_id.empty?
        @client.reply(status, "@#{sender_id} 전투 상대를 지정해주세요. 예: [전투/@상대방]")
        return true
      end
      
      if opponent_id == sender_id
        @client.reply(status, "@#{sender_id} 자신과는 전투할 수 없습니다!")
        return true
      end
      
      @battle_command.start_1v1(sender_id, opponent_id, status)
      return true
    end
    
    # GM 1:1 전투 - [전투/@A/@B] 형식 (GM이 다른 사람들끼리 전투)
    if content =~ /\[전투[\/\s]*(@?\w+)[\/\s]*(@?\w+)\]/i
      user1 = $1.gsub('@', '').strip
      user2 = $2.gsub('@', '').strip
      puts "[CommandParser] GM 1v1 전투: #{user1} vs #{user2}"
      
      unless GM_ACCOUNTS.include?(sender_id)
        @client.reply(status, "@#{sender_id} GM만 다른 사용자들끼리 전투를 시작할 수 있습니다.")
        return true
      end
      
      if user1 == user2
        @client.reply(status, "@#{sender_id} 같은 사용자끼리는 전투할 수 없습니다!")
        return true
      end
      
      @battle_command.start_1v1(user1, user2, status)
      return true
    end

    # 2:2 팀전투 개시
    if content =~ /\[팀전투[\/\s]*((?:@?\w+[\/\s]*){3}@?\w+)\]/i
      participants_text = $1
      puts "[CommandParser] 팀전투 참가자 텍스트: #{participants_text}"
      
      # 다양한 구분자로 분할
      participants = participants_text.split(/[\/\s]+/).map { |p| p.gsub('@', '').strip }.reject(&:empty?)
      puts "[CommandParser] 팀전투 참가자 목록: #{participants}"
      
      if participants.length != 4
        @client.reply(status, "@#{sender_id} 팀전투는 정확히 4명이 필요합니다. 현재: #{participants.length}명")
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
    if content =~ /\[대규모전투[\/\s]*((?:@?\w+[\/\s]*){7}@?\w+)\]/i
      participants_text = $1
      participants = participants_text.split(/[\/\s]+/).map { |p| p.gsub('@', '').strip }.reject(&:empty?)
      
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

    # 허수아비 전투
    if content =~ /\[허수아비\s+(상|중|하)\]/i
      difficulty = $1
      @client.reply(status, "@#{sender_id} 허수아비 전투는 아직 구현되지 않았습니다.")
      return true
    end

    false
  end

  def handle_battle_actions(content, status, sender_id)
    # 공격
    if content =~ /\[공격(?:[\/\s]*(@?\w+))?\]/i
      target = $1 ? $1.gsub('@', '').strip : nil
      @battle_command.attack(sender_id, target, status)
      return true
    end

    # 방어
    if content =~ /\[방어(?:[\/\s]*(@?\w+))?\]/i
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
    if content =~ /\[물약사용(?:[\/\s]*(소형|중형|대형))?(?:[\/\s]*(@?\w+))?\]/i
      potion_size = $1 || "소형"
      target = $2 ? $2.gsub('@', '').strip : nil
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

  def generate_hp_bar(current_hp, max_hp, bar_length = 10)
    return "█" * bar_length + " #{current_hp}/#{max_hp}" if current_hp >= max_hp
    return "░" * bar_length + " #{current_hp}/#{max_hp}" if current_hp <= 0 || max_hp <= 0
    
    filled_length = ((current_hp.to_f / max_hp.to_f) * bar_length).round
    empty_length = bar_length - filled_length
    
    "█" * filled_length + "░" * empty_length + " #{current_hp}/#{max_hp}"
  end
end
