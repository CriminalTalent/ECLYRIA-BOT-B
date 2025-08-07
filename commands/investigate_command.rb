# commands/investigate_command.rb

require 'date'
require_relative '../core/sheet_manager'

class InvestigateCommand
  def initialize(masto, sheet)
    @masto = masto
    @sheet = sheet
  end

  def handle(status)
    content = status[:content].gsub(/<[^>]+>/, '')
    user_id = status[:account][:acct]
    in_reply_to_id = status[:id]

    kind = detect_kind(content)
    target = detect_target(content)
    return unless kind && target

    today = Date.today.to_s
    last_date = SheetManager.get_stat(user_id, "마지막조사일")

    if last_date == today
      @masto.reply(user_id, "오늘은 이미 조사를 진행하셨습니다.", in_reply_to_id: in_reply_to_id)
      return
    end

    row = find_sheet_data(target, kind)
    unless row
      @masto.reply(user_id, "해당 대상에 대한 #{kind} 정보가 없습니다.", in_reply_to_id: in_reply_to_id)
      return
    end

    difficulty = row["난이도"].to_i
    stat = SheetManager.get_stat(user_id, "행운").to_i
    dice = rand(1..20)
    result_value = dice + stat

    if result_value >= difficulty
      result_text = row["성공결과"]
    else
      result_text = row["실패결과"]
    end

    SheetManager.set_stat(user_id, "마지막조사일", today)

    @masto.say("@#{user_id}의 #{kind} 결과: #{result_text} (주사위: #{dice}, 보정: #{stat}, 총합: #{result_value}/#{difficulty})")
  end

  private

  def detect_kind(text)
    case text
    when /정밀조사/ then "정밀조사"
    when /감지/ then "감지"
    when /훔쳐보기/ then "훔쳐보기"
    when /조사/ then "조사"
    else nil
    end
  end

  def detect_target(text)
    match = text.match(/\[(.+?)\]/)
    match && match[1]
  end

  def find_sheet_data(target, kind)
    sheet = @sheet.worksheet("조사")
    headers = sheet.rows[0]

    sheet.rows[1..].each do |row|
      row_hash = Hash[headers.zip(row)]
      next unless row_hash["대상"] == target

      # 조사 종류가 "조사"일 경우 "DM조사"도 허용
      if kind == "조사"
        return row_hash if ["조사", "DM조사"].include?(row_hash["종류"])
      else
        return row_hash if row_hash["종류"] == kind
      end
    end

    nil
  end
end
