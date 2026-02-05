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

    @service.client_options.open_timeout_sec = 10
    @service.client_options.read_timeout_sec = 10
    @service.client_options.send_timeout_sec = 10

    @stats_cache = nil
    @users_cache = nil
    @cache_time = nil
    @cache_ttl = 60
  end

  # --------------------
  # ID 정규화
  # - "@User" -> "user"
  # - "user@domain" -> "user"
  # - 대소문자/공백 통일
  # --------------------
  def normalize_id(raw)
    return nil if raw.nil?
    s = raw.to_s.strip
    s = s.sub(/\A@/, '')
    s = s.split('@', 2)[0]
    s = s.gsub(/\s+/, '')
    s.downcase
  end

  def load_all_data
    if @cache_time && (Time.now - @cache_time) < @cache_ttl
      return { stats: @stats_cache, users: @users_cache }
    end

    puts "[시트] 전체 데이터 로드 중..."
    start = Time.now

    # --------------------
    # 스탯 탭 로드
    # --------------------
    stats_range = '스탯!A:H'
    stats_response = @service.get_spreadsheet_values(@sheet_id, stats_range)

    # key는 정규화된 id로 저장
    stats_data = {}

    if stats_response.values
      stats_response.values[1..-1].each do |row|
        next if row.empty? || !row[0]

        raw_id = row[0]
        user_id = normalize_id(raw_id)
        next if user_id.nil? || user_id.empty?

        hp_stat = row[7] ? [[row[7].to_i, 0].max, 10].min : 0
        max_hp = 100 + (hp_stat * 10)

        stats_data[user_id] = {
          "ID" => raw_id, # 시트에 적힌 원본값 유지
          "이름" => row[1] || raw_id,
          "체력" => row[2] ? [[row[2].to_i, 0].max, max_hp].min.to_s : max_hp.to_s,
          "최대체력" => max_hp.to_s,
          "공격" => row[3] ? [[row[3].to_i, 0].max, 10].min.to_s : "0",
          "방어" => row[4] ? [[row[4].to_i, 0].max, 10].min.to_s : "0",
          "민첩" => row[5] ? [[row[5].to_i, 0].max, 10].min.to_s : "0",
          "행운" => row[6] ? [[row[6].to_i, 0].max, 10].min.to_s : "0",
          "체력스탯" => hp_stat.to_s
        }
      end
    end

    # --------------------
    # 사용자 탭 로드 (아이템)
    # --------------------
    user_range = '사용자!A:D'
    user_response = @service.get_spreadsheet_values(@sheet_id, user_range)
    users_data = {}

    if user_response.values
      user_response.values[1..-1].each do |row|
        next if row.empty? || !row[0]

        raw_id = row[0]
        user_id = normalize_id(raw_id)
        next if user_id.nil? || user_id.empty?

        users_data[user_id] = row[3] || ""
      end
    end

    @stats_cache = stats_data
    @users_cache = users_data
    @cache_time = Time.now

    elapsed = Time.now - start
    puts "[시트] 로드 완료 (#{elapsed.round(2)}초, 사용자 #{stats_data.size}명)"

    { stats: stats_data, users: users_data }
  rescue => e
    puts "[시트 오류] load_all_data 실패: #{e.message}"
    { stats: @stats_cache || {}, users: @users_cache || {} }
  end

  def find_user(raw_user_id)
    data = load_all_data
    user_id = normalize_id(raw_user_id)
    return nil if user_id.nil? || user_id.empty?

    user_data = data[:stats][user_id]
    return nil unless user_data

    user_data = user_data.dup
    user_data["아이템"] = data[:users][user_id] || ""
    user_data
  end

  # --------------------
  # 체력 업데이트: 시트에서는 "원본 ID" 행을 찾아야 하므로
  # - 비교 시에도 normalize해서 매칭
  # - 캐시는 normalize key로 갱신
  # --------------------
  def update_user_hp(raw_user_id, new_hp)
    user_id = normalize_id(raw_user_id)
    return false if user_id.nil? || user_id.empty?

    range = '스탯!A:H'
    response = @service.get_spreadsheet_values(@sheet_id, range)
    return false unless response.values

    response.values.each_with_index do |row, idx|
      next if idx == 0
      next if row.empty? || !row[0]

      row_id = normalize_id(row[0])
      next unless row_id == user_id

      hp_stat = row[7] ? [[row[7].to_i, 0].max, 10].min : 0
      max_hp = 100 + (hp_stat * 10)

      clamped_hp = [[new_hp, 0].max, max_hp].min
      cell_range = "스탯!C#{idx + 1}"
      value_range = Google::Apis::SheetsV4::ValueRange.new(values: [[clamped_hp]])

      @service.update_spreadsheet_value(
        @sheet_id,
        cell_range,
        value_range,
        value_input_option: 'RAW'
      )

      if @stats_cache && @stats_cache[user_id]
        @stats_cache[user_id]["체력"] = clamped_hp.to_s
        puts "[캐시] #{user_id} 체력 업데이트: #{clamped_hp}"
      end

      return true
    end

    false
  rescue => e
    puts "[시트 오류] HP 업데이트 실패: #{e.message}"
    false
  end

  def update_user_items(raw_user_id, items_string)
    user_id = normalize_id(raw_user_id)
    return false if user_id.nil? || user_id.empty?

    range = '사용자!A:D'
    response = @service.get_spreadsheet_values(@sheet_id, range)
    return false unless response.values

    response.values.each_with_index do |row, idx|
      next if idx == 0
      next if row.empty? || !row[0]

      row_id = normalize_id(row[0])
      next unless row_id == user_id

      cell_range = "사용자!D#{idx + 1}"
      value_range = Google::Apis::SheetsV4::ValueRange.new(values: [[items_string]])

      @service.update_spreadsheet_value(
        @sheet_id,
        cell_range,
        value_range,
        value_input_option: 'RAW'
      )

      if @users_cache
        @users_cache[user_id] = items_string
        puts "[캐시] #{user_id} 아이템 업데이트"
      end

      return true
    end

    false
  rescue => e
    puts "[시트 오류] 아이템 업데이트 실패: #{e.message}"
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

  def clear_cache
    @cache_time = nil
  end
end
