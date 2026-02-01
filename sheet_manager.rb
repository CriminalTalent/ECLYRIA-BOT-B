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
    
    # 타임아웃 설정
    @service.client_options.open_timeout_sec = 10
    @service.client_options.read_timeout_sec = 10
    @service.client_options.send_timeout_sec = 10
    
    # 캐시 초기화
    @stats_cache = nil
    @users_cache = nil
    @cache_time = nil
    @cache_ttl = 60
  end
  
  def load_all_data
    # 캐시가 유효하면 재사용
    if @cache_time && (Time.now - @cache_time) < @cache_ttl
      return { stats: @stats_cache, users: @users_cache }
    end
    
    puts "[시트] 전체 데이터 로드 중..."
    start = Time.now
    
    # 스탯 탭
    stats_range = '스탯!A:H'
    stats_response = @service.get_spreadsheet_values(@sheet_id, stats_range)
    stats_data = {}
    
    if stats_response.values
      stats_response.values[1..-1].each do |row|
        next if row.empty? || !row[0]
        user_id = row[0]
        
        hp_stat = row[7] ? [[row[7].to_i, 0].max, 10].min : 0
        max_hp = 100 + (hp_stat * 10)
        
        stats_data[user_id] = {
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
      end
    end
    
    # 사용자 탭 (D열: 아이템)
    user_range = '사용자!A:D'
    user_response = @service.get_spreadsheet_values(@sheet_id, user_range)
    users_data = {}
    
    if user_response.values
      user_response.values[1..-1].each do |row|
        next if row.empty? || !row[0]
        user_id = row[0]
        users_data[user_id] = row[3] || "" # D열: 아이템
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
    data = load_all_data
    user_data = data[:stats][user_id]
    return nil unless user_data
    
    # 아이템 정보 추가
    user_data = user_data.dup
    user_data["아이템"] = data[:users][user_id] || ""
    
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
        
        # 캐시 업데이트 (무효화 대신)
        if @stats_cache && @stats_cache[user_id]
          @stats_cache[user_id]["체력"] = clamped_hp.to_s
          puts "[캐시] #{user_id} 체력 업데이트: #{clamped_hp}"
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
    # 사용자 탭 D열에 아이템 업데이트
    range = '사용자!A:D'
    response = @service.get_spreadsheet_values(@sheet_id, range)
    return false unless response.values

    response.values.each_with_index do |row, idx|
      next if idx == 0
      if row[0] == user_id
        cell_range = "사용자!D#{idx + 1}"
        value_range = Google::Apis::SheetsV4::ValueRange.new(values: [[items_string]])
        @service.update_spreadsheet_value(
          @sheet_id,
          cell_range,
          value_range,
          value_input_option: 'RAW'
        )
        
        # 캐시 업데이트
        if @users_cache
          @users_cache[user_id] = items_string
          puts "[캐시] #{user_id} 아이템 업데이트"
        end
        
        return true
      end
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
