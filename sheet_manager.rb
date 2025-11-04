require 'google/apis/sheets_v4'
require 'googleauth'

class SheetManager
  def initialize(sheet_id, credentials_path)
    @sheet_id = sheet_id
    @service = Google::Apis::SheetsV4::SheetsService.new
    @service.authorization = Google::Auth::ServiceAccountCredentials.make_creds(
      json_key_io: File.open(credentials_path),
      scope: Google::Apis::SheetsV4::AUTH_SPREADSHEETS
    )
  end

  # === 기본 유틸 ===
  def read_values(range)
    result = @service.get_spreadsheet_values(@sheet_id, range)
    result.values
  rescue => e
    puts "[시트 읽기 오류] #{e.message}"
    nil
  end

  def update_values(range, values)
    value_range = Google::Apis::SheetsV4::ValueRange.new(values: values)
    @service.update_spreadsheet_value(
      @sheet_id, range, value_range,
      value_input_option: 'USER_ENTERED'
    )
  rescue => e
    puts "[시트 업데이트 오류] #{e.message}"
  end

  def append_values(range, values)
    value_range = Google::Apis::SheetsV4::ValueRange.new(values: values)
    @service.append_spreadsheet_value(
      @sheet_id, range, value_range,
      value_input_option: 'USER_ENTERED'
    )
  rescue => e
    puts "[시트 추가 오류] #{e.message}"
  end

  # === 사용자 관련 ===
  def find_user(user_id)
    values = read_values("사용자!A:J")
    return nil unless values
    headers = values[0]

    values.each_with_index do |row, index|
      next if index.zero?
      if row[0]&.gsub('@', '') == user_id.gsub('@', '')
        result = {}
        headers.each_with_index { |header, i| result[header] = row[i] }
        result['_row'] = index + 1
        return result
      end
    end
    nil
  end

  def get_stat(user_id, stat_name)
    user = find_user(user_id)
    return nil unless user
    user[stat_name]
  end

  def update_stat(user_id, stat_name, value)
    user = find_user(user_id)
    return unless user

    headers = read_values("사용자!A1:Z1")&.first
    return unless headers
    col_index = headers.index(stat_name)
    return unless col_index

    range = "사용자!#{number_to_column_letter(col_index + 1)}#{user['_row']}"
    update_values(range, [[value]])
  end

  # === 조사 관련 ===
  def find_investigation_entry(target, kind)
    values = read_values("조사!A:E")
    return nil unless values && !values.empty?

    headers = values[0]
    values.each_with_index do |row, index|
      next if index.zero?
      if row[0] == target && (row[1] == kind || (kind == "조사" && row[1] == "DM조사"))
        result = {}
        headers.each_with_index { |header, i| result[header] = row[i] }
        return result
      end
    end
    nil
  end

  # === 위치/세부조사 시스템 ===
  def is_location?(target)
    # "조사" 시트에서 세부 대상이 아닌 단독 위치를 식별
    values = read_values("조사!A:B")
    return false unless values
    targets = values.map { |r| r[0] }.compact
    !targets.include?(target) && targets.any? { |t| t.start_with?(target + " ") }
  end

  def find_details_in_location(location)
    values = read_values("조사!A:B")
    return [] unless values
    values.map { |r| r[0] }.compact.select { |t| t.start_with?(location + " ") }
  end

  def find_related_targets(target)
    return [] unless target.include?(" ")
    location_prefix = target.split(" ").first
    find_details_in_location(location_prefix).reject { |t| t == target }
  end

  private

  def number_to_column_letter(num)
    result = ""
    while num > 0
      num -= 1
      result = ((num % 26) + 65).chr + result
      num /= 26
    end
    result
  end
end

# === Worksheet Wrapper (보조용 클래스) ===
class WorksheetWrapper
  def initialize(sheet_manager, title)
    @sheet_manager = sheet_manager
    @title = title
    @data = nil
    load_data
  end

  def load_data
    @data = @sheet_manager.read_values("#{@title}!A:Z")
    @data ||= []
  end

  def rows
    load_data
    @data
  end

  def [](row, col)
    load_data
    return nil if row < 1 || row > @data.length
    return nil if col < 1 || col > (@data[row - 1]&.length || 0)
    @data[row - 1][col - 1]
  end

  def update_cell(row, col, value)
    range = "#{@title}!#{number_to_column_letter(col)}#{row}"
    @sheet_manager.update_values(range, [[value]])
    load_data
  end

  private

  def number_to_column_letter(num)
    result = ""
    while num > 0
      num -= 1
      result = ((num % 26) + 65).chr + result
      num /= 26
    end
    result
  end
end
