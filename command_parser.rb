# command_parser.rb

require_relative './commands/battle_command'
require_relative './commands/potion_command'
require_relative './commands/investigate_command'
require_relative './commands/dm_investigation_command'

class CommandParser
  def initialize(masto_client, sheet)
    @masto_client = masto_client
    @sheet = sheet

    # 명령 처리 클래스 초기화
    @battle = BattleCommand.new(@masto_client, @sheet)
    @potion = PotionCommand.new(@masto_client, @sheet)
    @investigate = InvestigateCommand.new(@masto_client, @sheet)
    @dm = DMInvestigationCommand.new(@masto_client)
  end

  def handle(status)
    content = status[:content]

    # 어떤 명령인지 파악해서 해당 커맨드 핸들러 호출
    if content.include?("전투개시") || content.match?(/공격|방어|반격|도주/)
      @battle.handle(status)

    elsif content.include?("물약사용")
      @potion.handle(status)

    elsif content.match?(/조사|정밀조사|감지|훔쳐보기/)
      @investigate.handle(status)

    elsif content.include?("DM조사결과")
      @dm.handle(status)
    end
  end
end

