# commands/dm_investigation_command.rb
require 'date'
require_relative '../core/sheet_manager'

class DMInvestigationCommand
  def initialize(masto)
    @masto = masto
  end

  def handle(status)
    content = status.content.gsub(/<[^>]+>/, '')
    return unless content.start_with?("DM조사결과")

    match = content.match(/DM조사결과\s+@(\w+)\s+(.+)/)
    return unless match

    user = match[1]
    result = match[2]
    today = Date.today.to_s

    SheetManager.set_stat(user, "마지막조사일", today)
    @masto.dm(user, result)
  end
end
