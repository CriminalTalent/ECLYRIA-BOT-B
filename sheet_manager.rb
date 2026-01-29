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
    # 스탯 탭에서 사용자 정보 읽기
    # A: ID, B: 이름, C: HP, D: 공격, E: 방어, F: 민첩, G: 행운, H: 체력
    stats_range = '스탯!A:H'
    stats_response = @service.get_spreadsheet_values(@sheet_id, stats_range)
    return nil unless stats_response.values

    user_data = nil
    stats_response.values[1..-1].each do |row|
      next if row.empty?
      if row[0] == user_id
        # 스탯 읽기 (0-10 범위로 제한)
        hp_stat = row[7] ? [[row[7].to_i, 0].max, 10].min : 0
        max_hp = 100 + (hp_stat * 10)
        
        user_data = {
          "ID" => row[0],
          "이름" => row[1] || user_id,
          "체력" => row[2] ? [[row[2].to_i, 0].max, max_hp].min.to_s : max_hp.to_s,
          "최대체력" => max_hp.to_s,
          "공격" => row[3] ? [[row[3].to_i, 0].max, 10].min.to_s : "0",
          "방어" => row[4] ? [[row[4].to_i, 0].max, 10].min.to_s : "0",
          "민첩" => row[5] ? [[row[5].to_i, 0].max, 10].min.to_s : "0",
          "행운" => row[6] ? [[row[6].to_i, 0].max, 10].min.to_s : "0",
          "체력스탯" => hp_stat.to_s
        }
        break
      end
    end
    
    return nil unless user_data
    
    # 사용자 탭에서 아이템 정보 읽기
    user_range = '사용자!A:J'
    user_response = @service.get_spreadsheet_values(@sheet_id, user_range)
    
    if user_response.values
      user_response.values[1..-1].each do |row|
        next if row.empty?
        if row[0] == user_id
          user_data["아이템"] = row[8] || "" # I열
          break
        end
      end
    end
    
    user_data
  end

  def update_user_hp(user_id, new_hp)
    # 스탯 탭에서 HP 업데이트
    range = '스탯!A:H'
    response = @service.get_spreadsheet_values(@sheet_id, range)
    return false unless response.values

    response.values.each_with_index do |row, idx|
      next if idx == 0
      if row[0] == user_id
        # H열에서 체력 스탯 읽기
        hp_stat = row[7] ? [[row[7].to_i, 0].max, 10].min : 0
        max_hp = 100 + (hp_stat * 10)
        
        # C열에 HP 업데이트 (최대 HP 제한)
        clamped_hp = [[new_hp, 0].max, max_hp].min
        cell_range = "스탯!C#{idx + 1}"
        value_range = Google::Apis::SheetsV4::ValueRange.new(values: [[clamped_hp]])
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
