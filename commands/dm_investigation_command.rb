# commands/dm_investigation_command.rb
require 'date'

class DMInvestigationCommand
  def initialize(mastodon_client, sheet_manager)
    @mastodon_client = mastodon_client
    @sheet_manager = sheet_manager
  end

  def handle(status)
    content = status.content.gsub(/<[^>]+>/, '').strip
    sender_full = status.account.acct
    sender = sender_full.split('@').first
    in_reply_to_id = status.id

    # DM조사결과 @유저 결과내용 파싱
    if content.match(/DM조사결과\s+@?(\w+)\s+(.+)/)
      target_user = $1
      result_text = $2
      
      # DM으로 결과 전송
      @mastodon_client.dm(target_user, "조사 결과: #{result_text}")
      
      # DM에게 확인 메시지
      @mastodon_client.dm(sender, "#{target_user}에게 조사 결과를 DM으로 전송했습니다.")
      
      puts "[DM조사] #{sender} -> #{target_user}: #{result_text}"
    else
      puts "[DM조사] 명령어 파싱 실패: #{content}"
    end
  end
end
