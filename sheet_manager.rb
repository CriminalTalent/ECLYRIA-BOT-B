# core/sheet_manager.rb
# 구글 시트 연동 (물약 아이템란 지원)

require 'google/apis/sheets_v4'
require 'googleauth'

class SheetManager
  SPREADSHEET_ID = ENV['GOOGLE_SHEET_ID'] || 'your-spreadsheet-id'
  USER_SHEET_NAME = '사용자'

  # 컬럼 매핑
  COLUMNS = {
    id: 'A',           # 아이디
    name: 'B',         # 이름
    hp: 'C',           # HP
    items: 'D',        # 아이템란 (물약)
    vitality: 'E',     # 체력
    attack: 'F',       # 공격
    defense: 'G',      # 방어
    agility: 'H',      # 민첩성
    luck: 'I'          # 행운
  }

  def initialize
    @service = Google::Apis::SheetsV4::SheetsService.new
    @service.authorization = authorize
  end

  # 사용자 찾기
  def find_user(user_id)
    range = "#{USER_SHEET_NAME}!A:I"

    begin
      response = @service.get_spreadsheet_values(SPREADSHEET_ID, range)
      values = response.values

      return nil if values.nil? || values.empty?

      header = values[0]
      rows = values[1..-1]

      rows.each_with_index do |row, index|
        if row[0] == user_id
          return build_user_hash(row, index + 2)
        end
      end

      nil
    rescue => e
      puts "[시트] 사용자 조회 실패: #{e.message}"
      nil
    end
  end

  # 모든 사용자 가져오기
  def get_all_users
    range = "#{USER_SHEET_NAME}!A:I"

    begin
      response = @service.get_spreadsheet_values(SPREADSHEET_ID, range)
      values = response.values

      return [] if values.nil? || values.empty?

      rows = values[1..-1]
      users = []

      rows.each_with_index do |row, index|
        next if row[0].nil? || row[0].strip.empty?
        users << build_user_hash(row, index + 2)
      end

      users
    rescue => e
      puts "[시트] 전체 사용자 조회 실패: #{e.message}"
      []
    end
  end

  # 사용자 정보 업데이트
  def update_user(user_id, updates)
    user = find_user(user_id)
    return false unless user

    row_number = user[:row_number]

    updates.each do |field, value|
      column = COLUMNS[field]
      next unless column

      cell_range = "#{USER_SHEET_NAME}!#{column}#{row_number}"

      begin
        value_range = Google::Apis::SheetsV4::ValueRange.new(values: [[value]])
        @service.update_spreadsheet_value(
          SPREADSHEET_ID,
          cell_range,
          value_range,
          value_input_option: 'RAW'
        )
      rescue => e
        puts "[시트] 업데이트 실패 (#{field}): #{e.message}"
        return false
      end
    end

    true
  end

  # ✅ 자정 데미지 활성화 여부 (전투설정!B2 체크박스)
  def midnight_damage_enabled?
    range = "'전투설정'!B2"
    begin
      value = @service.get_spreadsheet_values(SPREADSHEET_ID, range)&.values&.dig(0, 0)
      value.to_s.strip.upcase == 'TRUE'
    rescue => e
      puts "[시트오류] 자정 데미지 설정 읽기 실패: #{e.message}"
      false
    end
  end

  private

  # Google Sheets API 인증
  def authorize
    scopes = [Google::Apis::SheetsV4::AUTH_SPREADSHEETS]
    key_file = ENV['GOOGLE_APPLICATION_CREDENTIALS'] || 'credentials.json'

    authorizer = Google::Auth::ServiceAccountCredentials.make_creds(
      json_key_io: File.open(key_file),
      scope: scopes
    )

    authorizer.fetch_access_token!
    authorizer
  end

  # 행 데이터를 해시로 변환
  def build_user_hash(row, row_number)
    {
      "아이디" => row[0],
      "이름" => row[1],
      "HP" => row[2]&.to_i || 0,
      "아이템" => row[3] || "",
      "체력" => row[4]&.to_i || 10,
      "공격" => row[5]&.to_i || 10,
      "방어" => row[6]&.to_i || 10,
      "민첩성" => row[7]&.to_i || 10,
      "행운" => row[8]&.to_i || 10,
      row_number: row_number
    }
  end
end
