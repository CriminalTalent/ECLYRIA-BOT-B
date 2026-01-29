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
    
    mentioned_users = extract_mentions(clean_text)
    
    if clean_text =~ /GM전투개시/i || clean_text =~ /GM\s*전투\s*개시/i
      participants = [sender] + mentioned_users
      @battle_engine.start_pvp(status, participants, is_gm: true)
    elsif clean_text =~ /전투개시/i || clean_text =~ /전투\s*개시/i
      participants = [sender] + mentioned_users
      @battle_engine.start_pvp(status, participants)
    elsif clean_text =~ /GM전투중단/i || clean_text =~ /GM\s*전투\s*중단/i
      @battle_engine.stop_battle(sender, status)
    elsif clean_text =~ /공격/i
      target = mentioned_users.first
      @battle_engine.attack(sender, status, target)
    elsif clean_text =~ /방어/i
      @battle_engine.defend(sender, status)
    elsif clean_text =~ /반격/i
      @battle_engine.counter(sender, status)
    elsif clean_text =~ /도주/i
      @battle_engine.flee(sender, status)
    elsif clean_text =~ /물약/i
      target = mentioned_users.first
      @battle_engine.use_potion(sender, status, target)
    end
  end

  private

  def strip_html(html)
    html.gsub(/<[^>]+>/, ' ').gsub(/\s+/, ' ').strip
  end

  def extract_mentions(text)
    text.scan(/@(\w+)/).flatten.map(&:strip).uniq
  end
end
