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
    
    # 대괄호 안의 전체 내용 추출
    bracket_content = extract_bracket_content(clean_text)
    
    unless bracket_content
      puts "[파서] 대괄호 없음 - 무시"
      return
    end
    
    puts "[파서] 대괄호 내용: #{bracket_content}"
    
    # 슬래시로 분리
    parts = bracket_content.split('/')
    command = parts[0].strip
    params = parts[1..-1].map { |p| p.gsub('@', '').strip } if parts.length > 1
    params ||= []
    
    puts "[파서] 명령어: #{command}"
    puts "[파서] 파라미터: #{params.inspect}"
    
    # 추가로 본문에서 멘션 추출 (전투개시용)
    mentioned_users = extract_mentions(clean_text)
    puts "[파서] 본문 멘션: #{mentioned_users.inspect}"

    # 체력 확인
    if command =~ /^체력$/i
      @battle_engine.check_hp(sender, status)
    # 전투개시 명령어
    elsif command =~ /^전투개시$/i
      # 대괄호 안의 파라미터가 있으면 그것 사용, 없으면 본문 멘션 사용
      participants = params.empty? ? mentioned_users : params
      @battle_engine.start_pvp(status, participants, is_gm: true, gm_user: sender)
    # 전투중단
    elsif command =~ /^전투중단$/i
      @battle_engine.stop_battle(sender, status)
    # 공격
    elsif command =~ /^공격$/i
      target = params.first
      @battle_engine.attack(sender, status, target)
    # 방어
    elsif command =~ /^방어$/i
      target = params.first
      @battle_engine.defend(sender, status, target)
    # 반격
    elsif command =~ /^반격$/i
      @battle_engine.counter(sender, status)
    # 도주
    elsif command =~ /^도주$/i
      @battle_engine.flee(sender, status)
    # 물약사용
    elsif command =~ /^물약사용$/i
      potion_size = params[0]
      target = params[1]
      @battle_engine.use_potion(sender, status, potion_size, target)
    else
      puts "[파서] 알 수 없는 명령어: #{command}"
    end
  end

  private

  def strip_html(html)
    html.gsub(/<[^>]+>/, ' ').gsub(/\s+/, ' ').strip
  end

  # 대괄호 안의 전체 내용 추출
  def extract_bracket_content(text)
    match = text.match(/\[([^\]]+)\]/)
    return nil unless match
    match[1].strip
  end

  def extract_mentions(text)
    text.scan(/@(\w+)/).flatten.map(&:strip).uniq
  end
end
