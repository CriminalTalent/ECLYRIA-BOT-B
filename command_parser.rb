# command_parser.rb
require_relative 'commands/battle_command'
require_relative 'commands/potion_command'
require_relative 'commands/investigate_command'
require_relative 'commands/enhanced_investigate_command'
require_relative 'commands/dm_investigation_command'

class CommandParser
  def initialize(mastodon_client, sheet_manager)
    @mastodon_client = mastodon_client
    @sheet_manager = sheet_manager
    
    # 명령 처리 클래스 초기화
    @battle = BattleCommand.new(@mastodon_client, @sheet_manager)
    @potion = PotionCommand.new(@mastodon_client, @sheet_manager)
    @investigate = InvestigateCommand.new(@mastodon_client, @sheet_manager)
    @enhanced_investigate = EnhancedInvestigateCommand.new(@mastodon_client, @sheet_manager)
    @dm = DMInvestigationCommand.new(@mastodon_client, @sheet_manager)
  end

  def handle(status)
    content = status.content.gsub(/<[^>]*>/, '').strip
    sender_full = status.account.acct
    
    # sender ID 정규화 (@domain 부분 제거)
    sender = sender_full.split('@').first
    
    puts "[전투봇] 처리 중: #{content} (from @#{sender_full} -> #{sender})"
    
    # 명령어 라우팅
    case content
    when /전투개시|허수아비|공격\/|방어\/|공격|방어|반격|도주/
      @battle.handle(status)
    when /물약사용/
      @potion.handle(status)
    when /DM조사결과/
      @dm.handle(status)
    when /이동\/|위치확인|주변탐색|은신|협력조사\/|방해\/|물건이동\/|숨기기\/|흔적조사\/|조사기록\/|타임라인\//
      # 고도화된 조사 시스템 명령어들
      @enhanced_investigate.handle(status)
    when /조사\/|정밀조사\/|감지\/|훔쳐보기\//
      # 기존 조사 명령어는 고도화된 시스템으로 처리
      @enhanced_investigate.handle(status)
    else
      puts "[무시] 인식되지 않은 명령어: #{content}"
    end
  end
end
