# commands/dm_investigation_command.rb

class DMInvestigationCommand
  def initialize(masto_client)
    @client = masto_client
  end

  def handle(status)
    content = status[:content]
    author_id = status[:account][:acct]

    # DM만 실행 가능하도록 제한 (선택사항)
    return unless is_dm?(author_id)

    if content =~ /^DM조사결과\s+@(\w+)\s+(.+)/
      target_id = "@#{$1}"
      result = $2.strip

      post_dm_result(target_id, result)
    end
  end

  private

  def is_dm?(user_id)
    # 🟢 이 부분은 원하는 DM 계정으로 제한할 수도 있습니다
    ["dm", "game_master", "admin"].include?(user_id)
  end

  def post_dm_result(user_id, result)
    message = "@#{user_id} 조사 결과입니다:\n\n🧾 #{result}"
    @client.create_status(message)
  end
end

