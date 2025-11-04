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

  # === 조사 데이터 ===
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

  def is_location?(target)
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

  # === 조사 로그 기록 ===
  def log_investigation(user_id, location, target, kind, success, result_text)
    time = Time.now.strftime('%Y-%m-%d %H:%M')
    outcome = success ? "성공" : "실패"
    values = [[time, user_id, location, target, kind, outcome, result_text]]
    append_values("조사로그!A:G", values)
    puts "[로그기록] #{user_id} / #{target} / #{kind} → #{outcome}"
  rescue => e
    puts "[조사로그 기록 오류] #{e.message}"
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
