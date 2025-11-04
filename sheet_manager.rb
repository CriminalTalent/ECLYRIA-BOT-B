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

  def read_values(range)
    @service.get_spreadsheet_values(@sheet_id, range).values
  rescue
    nil
  end

  def update_values(range, values)
    range_obj = Google::Apis::SheetsV4::ValueRange.new(values: values)
    @service.update_spreadsheet_value(@sheet_id, range, range_obj, value_input_option: 'USER_ENTERED')
  end

  def append_values(range, values)
    range_obj = Google::Apis::SheetsV4::ValueRange.new(values: values)
    @service.append_spreadsheet_value(@sheet_id, range, range_obj, value_input_option: 'USER_ENTERED')
  end

  # === 사용자 ===
  def find_user(user_id)
    rows = read_values("사용자!A:J")
    return nil unless rows
    headers = rows[0]
    rows.each_with_index do |r, i|
      next if i == 0
      if r[0]&.gsub('@', '') == user_id.gsub('@', '')
        h = {}
        headers.each_with_index { |hname, j| h[hname] = r[j] }
        h["_row"] = i + 1
        return h
      end
    end
    nil
  end

  # === 조사 기능 ===
  def is_location?(target)
    rows = read_values("조사!A:A")
    rows.flatten.compact.include?(target)
  end

  def available_locations
    rows = read_values("조사!A:A")
    rows.flatten.compact.uniq
  end

  def find_details_in_location(location)
    rows = read_values("조사!A:B")
    rows.select { |r| r[0] == location && r[1] && !r[1].empty? }.map { |r| r[1] }.uniq
  end

  def find_investigation_entry(target, kind)
    rows = read_values("조사!A:G")
    return nil unless rows && !rows.empty?
    headers = rows[0]
    rows.each_with_index do |r, i|
      next if i == 0
      if r[1] == target && r[3] == kind
        data = {}
        headers.each_with_index { |h, j| data[h] = r[j] }
        return data
      end
    end
    nil
  end

  # === 조사상태 ===
  def get_investigation_state(user_id)
    rows = read_values("조사상태!A:C")
    headers = rows[0]
    record = rows.find { |r| r[0] == user_id }
    return {} unless record
    Hash[headers.zip(record)]
  end

  def update_investigation_state(user_id, state, location)
    rows = read_values("조사상태!A:C")
    idx = rows.find_index { |r| r[0] == user_id }
    return unless idx
    update_values("조사상태!B#{idx+1}:C#{idx+1}", [[state, location]])
  end

  # === 로그 ===
  def log_investigation(user_id, location, target, kind, success, result)
    time = Time.now.strftime('%Y-%m-%d %H:%M')
    outcome = success ? "성공" : "실패"
    append_values("조사로그!A:G", [[time, user_id, location, target, kind, outcome, result]])
  end
end
