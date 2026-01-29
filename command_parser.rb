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
    
    # 대괄호 안의 명령어 추출
    command = extract_command(clean_text)
    return unless command
    
    mentioned_users = extract_mentions(clean_text)
    
    # 전투개시 명령어
    if command =~ /^전투개시$/i
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
    elsif command =~ /^방어$/i
      @battle_engine.defend(sender, status)
      
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
