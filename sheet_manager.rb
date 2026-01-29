require 'google/apis/sheets_v4'
require 'googleauth'

class SheetManager
  SCOPES = [Google::Apis::SheetsV4::AUTH_SPREADSHEETS]

  def initialize(sheet_id, credentials_path)
    @sheet_id = sheet_id
    @service = Google::Apis::SheetsV4::SheetsService.new
    @service.authorization = Google::Auth::ServiceAccountCredentials.make_creds(
      json_key_io: File.open(credentials_path),
      scope: SCOPES
    )
  end

  def find_user(user_id)
    range = '사용자!A:J'
    response = @service.get_spreadsheet_values(@sheet_id, range)
    return nil unless response.values

    headers = response.values[0]
    response.values[1..-1].each do |row|
      next if row.empty?
      if row[0] == user_id
        user_data = {}
        headers.each_with_index do |header, idx|
          user_data[header] = row[idx]
        end
        return user_data
      end
    end
    nil
  end

  def update_user_hp(user_id, new_hp)
    range = '사용자!A:J'
    response = @service.get_spreadsheet_values(@sheet_id, range)
    return false unless response.values

    response.values.each_with_index do |row, idx|
      next if idx == 0
      if row[0] == user_id
        cell_range = "사용자!C#{idx + 1}"
        value_range = Google::Apis::SheetsV4::ValueRange.new(values: [[new_hp]])
        @service.update_spreadsheet_value(
          @sheet_id,
          cell_range,
          value_range,
          value_input_option: 'RAW'
        )
        return true
      end
    end
    false
  rescue => e
    puts "[시트 오류] HP 업데이트 실패: #{e.message}"
    false
  end

  def get_all_users
    range = '사용자!A:J'
    response = @service.get_spreadsheet_values(@sheet_id, range)
    return [] unless response.values

    headers = response.values[0]
    users = []

    response.values[1..-1].each do |row|
      next if row.empty?
      user_data = {}
      headers.each_with_index do |header, idx|
        user_data[header] = row[idx]
      end
      users << user_data
    end
    users
  end
end
