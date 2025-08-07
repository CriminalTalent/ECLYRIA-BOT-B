# commands/investigate_command.rb

require_relative '../core/sheet_manager'

class InvestigateCommand
  def initialize(masto_client, sheet)
    @client = masto_client
    @sheet = sheet
  end

  def handle(status)
    content = status[:content]
    user_id = status[:account][:acct]

    case content
    when /^조사\s+(.+)/
      handle_investigation(user_id, $1.strip, "조사")

    when /^정밀조사\s+(.+)/
      handle_investigation(user_id, $1.strip, "정밀조사")

    when /^감지\s+(.+)/
      handle_investigation(user_id, $1.strip, "감지")

    when /^훔쳐보기\s+@(\w+)/
      handle_peek(user_id, "@#{$1}")

    else
      # 무시
      return
    end
  end

  private

  def handle_investigation(user_id, target, kind)
    return unless can_investigate?(user_id)

    data = find_sheet_data(target, kind)
    if data.nil?
      @client.reply("@#{user_id} 조사할 수 없는 대상입니다.")
      return
    end

    luck = SheetManager.get_stat(user_id, "행운")
    roll = luck + rand(1..20)
    success = roll >= data[:difficulty]

    result = if success
               data[:success].sample
             else
               data[:failure].sample
             end

    SheetManager.set_stat(user_id, "마지막조사일", Date.today.to_s)

    message = "@#{user_id}의 #{kind} 결과 \n\n#{result}"
    @client.create_status(message)
  end

  def can_investigate?(user_id)
    today = Date.today.to_s
    last = SheetManager.get_stat(user_id, "마지막조사일")

    if last == today
      @client.reply("@#{user_id} 오늘은 이미 조사를 진행했습니다.")
      return false
    end

    true
  end

  def find_sheet_data(target, kind)
    rows = @sheet.worksheet("조사").rows
    headers = rows[0]
    rows[1..].each do |row|
      row_data = Hash[headers.zip(row)]
      next unless row_data["대상"] == target && row_data["종류"] == kind

      return {
        difficulty: row_data["난이도"].to_i,
        success: [row_data["성공결과1"], row_data["성공결과2"]].compact,
        failure: [row_data["실패결과1"], row_data["실패결과2"]].compact
      }
    end

    nil
  end

  def handle_peek(user_id, target_id)
    luck = SheetManager.get_stat(user_id, "행운") + rand(1..20)
    detect = rand(1..20)

    msg = if luck > detect
            "@#{user_id}는 @#{target_id}를 몰래 관찰하는 데 성공했습니다. 무언가를 알아냈습니다."
          else
            "@#{user_id}의 훔쳐보기 실패. 들켰습니다."
          end

    @client.create_status(msg)
  end
end
