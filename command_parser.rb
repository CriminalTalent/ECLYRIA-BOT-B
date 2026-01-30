require_relative 'core/battle_engine'

class CommandParser
  def initialize(mastodon_client, sheet_manager)
    @mastodon_client = mastodon_client
    @sheet_manager = sheet_manager
    @battle_engine = BattleEngine.new(mastodon_client, sheet_manager)
  end

  def handle(status)
    content = status[:content]
    sender = status[:account][:acct]
    
    clean_text = strip_html(content)
    puts "[파서] 원본 HTML: #{content[0..200]}"
    puts "[파서] HTML 제거: #{clean_text}"
    
    # 대괄호 안의 명령어 추출
    command = extract_command(clean_text)
    
    unless command
      puts "[파서] 명령어 없음 - 무시"
      return
    end
    
    puts "[파서] 추출된 명령어: #{command}"
    
    mentioned_users = extract_mentions(clean_text)
    puts "[파서] 멘션된 사용자: #{mentioned_users.inspect}"

    # 체력 확인
    if command =~ /^체력$/i
      @battle_engine.check_hp(sender, status)
    # 전투개시 명령어
    elsif command =~ /^전투개시$/i
      # GM은 참가자에서 제외
      participants = mentioned_users
      @battle_engine.start_pvp(status, participants, is_gm: true, gm_user: sender)
    # 전투중단
    elsif command =~ /^전투중단$/i
      @battle_engine.stop_battle(sender, status)
    # 공격
    elsif command =~ /^공격(\/)?(.*)$/i
      target_match = $2
      if target_match && !target_match.empty?
        # 공격/@타겟 형식
        target = target_match.gsub('@', '').strip
        @battle_engine.attack(sender, status, target)
      else
        # 공격 (타겟 없음)
        @battle_engine.attack(sender, status, nil)
      end
    # 방어
    elsif command =~ /^방어(\/)?(.*)$/i
      target_match = $2
      if target_match && !target_match.empty?
        # 방어/@아군 형식 (대리 방어)
        target = target_match.gsub('@', '').strip
        @battle_engine.defend(sender, status, target)
      else
        # 방어 (자신)
        @battle_engine.defend(sender, status, nil)
      end
    # 반격
    elsif command =~ /^반격$/i
      @battle_engine.counter(sender, status)
    # 도주
    elsif command =~ /^도주$/i
      @battle_engine.flee(sender, status)
    # 물약사용
    elsif command =~ /^물약사용\/(소형|중형|대형)(\/)?(.*)$/i
      potion_size = $1
      target_match = $3
      if target_match && !target_match.empty?
        # 물약사용/크기/@타겟 형식
        target = target_match.gsub('@', '').strip
        @battle_engine.use_potion(sender, status, potion_size, target)
      else
        # 물약사용/크기 (본인)
        @battle_engine.use_potion(sender, status, potion_size, nil)
      end
    else
      puts "[파서] 알 수 없는 명령어: #{command}"
    end
  end

  private

  def strip_html(html)
    html.gsub(/<[^>]+>/, ' ').gsub(/\s+/, ' ').strip
  end

  # 대괄호 안의 명령어 추출
  def extract_command(text)
    match = text.match(/\[([^\]]+)\]/)
    return nil unless match
    match[1].strip
  end

  def extract_mentions(text)
    text.scan(/@(\w+)/).flatten.map(&:strip).uniq
  end
end
