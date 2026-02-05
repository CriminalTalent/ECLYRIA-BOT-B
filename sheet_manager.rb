# sheet_manager.rb
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

  def norm_id(s)
    return "" if s.nil?
    s.to_s.strip.downcase
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
    stats_data = {}

    if stats_response.values
      stats_response.values[1..-1].each do |row|
        next if row.empty? || !row[0]
        raw_user_id = row[0].to_s.strip
        key = norm_id(raw_user_id)

        hp_stat = row[7] ? [[row[7].to_i, 0].max, 10].min : 0
        max_hp = 100 + (hp_stat * 10)

        stats_data[key] = {
          "ID" => raw_user_id,                 # 원본 보존
          "이름" => row[1] || raw_user_id,
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
        raw_user_id = row[0].to_s.strip
        key = norm_id(raw_user_id)
        users_data[key] = (row[3] || "").to_s
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

  def find_user(user_id)
    key = norm_id(user_id)
    data = load_all_data

    user_data = data[:stats][key]
    unless user_data
      puts "[시트] 사용자 없음: #{key}"
      return nil
    end

    puts "[시트] 사용자 찾음: #{key}"

    user_data = user_data.dup
    user_data["아이템"] = data[:users][key] || ""
    user_data
  end

  def update_user_hp(user_id, new_hp)
    key = norm_id(user_id)

    range = '스탯!A:H'
    response = @service.get_spreadsheet_values(@sheet_id, range)
    return false unless response.values

    response.values.each_with_index do |row, idx|
      next if idx == 0
      next unless row[0]

      row_key = norm_id(row[0])
      if row_key == key
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

        if @stats_cache && @stats_cache[key]
          @stats_cache[key]["체력"] = clamped_hp.to_s
          puts "[캐시] #{key} 체력 업데이트: #{clamped_hp}"
        end

        return true
      end
    end
    false
  rescue => e
    puts "[시트 오류] HP 업데이트 실패: #{e.message}"
    false
  end

  def update_user_items(user_id, items_string)
    key = norm_id(user_id)

    range = '사용자!A:D'
    response = @service.get_spreadsheet_values(@sheet_id, range)
    return false unless response.values

    response.values.each_with_index do |row, idx|
      next if idx == 0
      next unless row[0]

      row_key = norm_id(row[0])
      if row_key == key
        cell_range = "사용자!D#{idx + 1}"
        value_range = Google::Apis::SheetsV4::ValueRange.new(values: [[items_string.to_s]])
        @service.update_spreadsheet_value(
          @sheet_id,
          cell_range,
          value_range,
          value_input_option: 'RAW'
        )

        if @users_cache
          @users_cache[key] = items_string.to_s
          puts "[캐시] #{key} 아이템 업데이트"
        end

        return true
      end
    end
    false
  rescue => e
    puts "[시트 오류] 아이템 업데이트 실패: #{e.message}"
    false
  end

  def clear_cache
    @cache_time = nil
  end
end
