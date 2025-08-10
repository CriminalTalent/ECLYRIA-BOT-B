# commands/dm_investigation_command.rb
require 'date'

class DMInvestigationCommand
  def initialize(mastodon_client, sheet_manager)
    @mastodon_client = mastodon_client
    @sheet_manager = sheet_manager
  end

  def handle(status)
    content = status.content.gsub(/<[^>]+>/, '').strip
    return unless content.start_with?("DM조사결과")

    match = content.match(/DM조사결과\s+@?(\w+)\s+(.+)/)
    return unless match

    user = match[1]
    result = match[2]
    today = Date.today.to_s

    @sheet_manager.set_stat(user, "마지막조사일", today)
    @mastodon_client.dm(user, result)
    puts "[DM조사] #{user}에게 결과 전송 완료"
  end
end
