# sheet_manager.rb
require 'google/apis/sheets_v4'
require 'googleauth'
require 'json'

class SheetManager
  CACHE_TTL = 30  # cache TTL (seconds)

  def initialize(spreadsheet_id = nil, credentials_path = nil)
    @spreadsheet_id = spreadsheet_id || ENV['GOOGLE_SHEET_ID']
    @credentials_path = credentials_path || ENV['GOOGLE_CREDENTIALS_PATH'] || 'credentials.json'

    # Google Sheets API 초기화
    @sheets_service = Google::Apis::SheetsV4::SheetsService.new
    @sheets_service.authorization = authorize

    @mutex = Mutex.new
    @cache = {}
    @cache_time = {}

    puts "[SheetManager] 초기화 완료 (캐시 TTL: #{CACHE_TTL}초)"
  end

  private

  def authorize
    scope = Google::Apis::SheetsV4::AUTH_SPREADSHEETS
    authorizer = Google::Auth::ServiceAccountCredentials.make_creds(
      json_key_io: File.open(@credentials_path),
      scope: scope
    )
    authorizer.fetch_access_token!
    authorizer
  end

  public

  # validation
  def cache_valid?(key)
    return false unless @cache_time[key]
    Time.now - @cache_time[key] < CACHE_TTL
  end

  # update cache (with retry on quota error)
  def refresh_cache(retry_count = 0)
    @mutex.synchronize do
      begin
        # 스탯 시트
        stats_range = "'스탯'!A2:H1000"
        stats_response = @sheets_service.get_spreadsheet_values(@spreadsheet_id, stats_range)
        @cache[:stats] = stats_response.values || []
        @cache_time[:stats] = Time.now

        # 사용자 시트
        user_range = "'사용자'!A2:D1000"
        user_response = @sheets_service.get_spreadsheet_values(@spreadsheet_id, user_range)
        @cache[:users] = user_response.values || []
        @cache_time[:users] = Time.now

        puts "[SheetManager] 캐시 갱신 완료"
        true
      rescue Google::Apis::RateLimitError, Google::Apis::ClientError => e
        if e.message.include?("RESOURCE_EXHAUSTED") && retry_count < 3
          wait_time = (retry_count + 1) * 10  # 10초, 20초, 30초
          puts "[SheetManager] 할당량 초과, #{wait_time}초 후 재시도 (#{retry_count + 1}/3)"
          sleep wait_time
          return refresh_cache(retry_count + 1)
        end
        puts "[SheetManager] 캐시 갱신 오류: #{e.message}"
        false
      rescue => e
        puts "[SheetManager] 캐시 갱신 오류: #{e.message}"
        false
      end
    end
  end

  # 캐시 무효화 (업데이트 후 호출)
  def invalidate_cache
    @cache_time[:stats] = nil
    @cache_time[:users] = nil
  end

  # 사용자 검색 (ID로 검색, 스탯 + 사용자 시트 통합) - 캐시 사용
  def find_user(user_id)
    # 캐시가 없거나 만료되었으면 갱신
    unless cache_valid?(:stats) && cache_valid?(:users)
      refresh_cache
    end

    @mutex.synchronize do
      begin
        stats_values = @cache[:stats]
        return nil unless stats_values

        stats_row = stats_values.find { |row| row[0] == user_id }
        return nil unless stats_row

        user_values = @cache[:users]
        user_row = user_values&.find { |row| row[0] == user_id }

        return {
          "ID" => stats_row[0],                         # A열: ID
          "이름" => stats_row[1] || user_id,            # B열: 이름
          "HP" => (stats_row[2] || "100").to_i,         # C열: 현재 체력
          "공격" => (stats_row[3] || "10").to_i,        # D열: 공격
          "방어" => (stats_row[4] || "10").to_i,        # E열: 방어
          "민첩성" => (stats_row[5] || "10").to_i,      # F열: 민첩
          "행운" => (stats_row[6] || "10").to_i,        # G열: 행운
          "체력" => (stats_row[7] || "10").to_i,        # H열: 체력 (최대HP용)
          "갈레온" => user_row ? (user_row[2] || "0").to_i : 0,     # 사용자 C열
          "아이템" => user_row ? (user_row[3] || "") : ""            # 사용자 D열
        }
      rescue => e
        puts "[SheetManager] 사용자 검색 오류: #{e.message}"
        puts e.backtrace[0..3]
        nil
      end
    end
  end

  # 사용자 정보 업데이트
  def update_user(user_id, updates)
    @mutex.synchronize do
      begin
        success = true
        
        # 스탯 시트 업데이트
        stats_updates = {}
        user_updates = {}
        
        updates.each do |key, value|
          case key
          when "HP", "현재체력"
            stats_updates["C"] = value
          when "공격"
            stats_updates["D"] = value
          when "방어"
            stats_updates["E"] = value
          when "민첩성", "민첩"
            stats_updates["F"] = value
          when "행운"
            stats_updates["G"] = value
          when "체력"
            stats_updates["H"] = value
          when "갈레온"
            user_updates["C"] = value
          when "아이템"
            user_updates["D"] = value
          end
        end
        
        # 스탯 시트 업데이트
        if stats_updates.any?
          stats_range = "'스탯'!A2:H1000"
          stats_response = @sheets_service.get_spreadsheet_values(@spreadsheet_id, stats_range)
          stats_values = stats_response.values
          
          if stats_values
            row_index = stats_values.find_index { |row| row[0] == user_id }
            
            if row_index
              actual_row = row_index + 2
              
              stats_updates.each do |col, value|
                cell_range = "'스탯'!#{col}#{actual_row}"
                value_range = Google::Apis::SheetsV4::ValueRange.new(values: [[value]])
                
                @sheets_service.update_spreadsheet_value(
                  @spreadsheet_id,
                  cell_range,
                  value_range,
                  value_input_option: 'USER_ENTERED'
                )
                
                puts "[SheetManager] #{user_id}의 스탯 업데이트: #{col}열 = #{value}"
              end
            else
              success = false
            end
          end
        end
        
        # 사용자 시트 업데이트
        if user_updates.any?
          user_range = "'사용자'!A2:D1000"
          user_response = @sheets_service.get_spreadsheet_values(@spreadsheet_id, user_range)
          user_values = user_response.values
          
          if user_values
            row_index = user_values.find_index { |row| row[0] == user_id }
            
            if row_index
              actual_row = row_index + 2
              
              user_updates.each do |col, value|
                cell_range = "'사용자'!#{col}#{actual_row}"
                value_range = Google::Apis::SheetsV4::ValueRange.new(values: [[value]])
                
                @sheets_service.update_spreadsheet_value(
                  @spreadsheet_id,
                  cell_range,
                  value_range,
                  value_input_option: 'USER_ENTERED'
                )
                
                puts "[SheetManager] #{user_id}의 사용자 정보 업데이트: #{col}열 = #{value}"
              end
            else
              success = false
            end
          end
        end
        
        # if update successful, invalidate cache
        invalidate_cache if success

        success
      rescue => e
        puts "[SheetManager] 사용자 업데이트 오류: #{e.message}"
        puts e.backtrace[0..3]
        false
      end
    end
  end

  # 모든 사용자 목록 가져오기
  def list_users
    @mutex.synchronize do
      begin
        stats_range = "'스탯'!A2:H1000"
        stats_response = @sheets_service.get_spreadsheet_values(@spreadsheet_id, stats_range)
        stats_values = stats_response.values
        
        return [] unless stats_values
        
        user_range = "'사용자'!A2:D1000"
        user_response = @sheets_service.get_spreadsheet_values(@spreadsheet_id, user_range)
        user_values = user_response.values
        
        stats_values.map do |stats_row|
          user_id = stats_row[0]
          user_row = user_values&.find { |row| row[0] == user_id }
          
          {
            "ID" => user_id,
            "이름" => stats_row[1] || user_id,
            "HP" => (stats_row[2] || "100").to_i,
            "공격" => (stats_row[3] || "10").to_i,
            "방어" => (stats_row[4] || "10").to_i,
            "민첩성" => (stats_row[5] || "10").to_i,
            "행운" => (stats_row[6] || "10").to_i,
            "체력" => (stats_row[7] || "10").to_i,
            "갈레온" => user_row ? (user_row[2] || "0").to_i : 0,
            "아이템" => user_row ? (user_row[3] || "") : ""
          }
        end
      rescue => e
        puts "[SheetManager] 사용자 목록 오류: #{e.message}"
        []
      end
    end
  end

  # 사용자 존재 확인
  def user_exists?(user_id)
    !find_user(user_id).nil?
  end

  # 배치 업데이트 (여러 사용자 동시 업데이트)
  def batch_update_users(updates_hash)
    @mutex.synchronize do
      begin
        batch_data = []
        
        # 스탯 시트 데이터 가져오기
        stats_range = "'스탯'!A2:H1000"
        stats_response = @sheets_service.get_spreadsheet_values(@spreadsheet_id, stats_range)
        stats_values = stats_response.values
        
        # 사용자 시트 데이터 가져오기
        user_range = "'사용자'!A2:D1000"
        user_response = @sheets_service.get_spreadsheet_values(@spreadsheet_id, user_range)
        user_values = user_response.values
        
        return false unless stats_values
        
        updates_hash.each do |user_id, user_updates|
          # 스탯 시트 업데이트
          stats_row_index = stats_values.find_index { |row| row[0] == user_id }
          
          if stats_row_index
            actual_row = stats_row_index + 2
            
            user_updates.each do |key, value|
              col = case key
                    when "HP", "현재체력" then "C"
                    when "공격" then "D"
                    when "방어" then "E"
                    when "민첩성", "민첩" then "F"
                    when "행운" then "G"
                    when "체력" then "H"
                    else nil
                    end
              
              if col
                batch_data << {
                  range: "'스탯'!#{col}#{actual_row}",
                  values: [[value]]
                }
              end
            end
          end
          
          # 사용자 시트 업데이트
          if user_values
            user_row_index = user_values.find_index { |row| row[0] == user_id }
            
            if user_row_index
              actual_row = user_row_index + 2
              
              user_updates.each do |key, value|
                col = case key
                      when "갈레온" then "C"
                      when "아이템" then "D"
                      else nil
                      end
                
                if col
                  batch_data << {
                    range: "'사용자'!#{col}#{actual_row}",
                    values: [[value]]
                  }
                end
              end
            end
          end
        end
        
        if batch_data.any?
          batch_update_request = Google::Apis::SheetsV4::BatchUpdateValuesRequest.new(
            data: batch_data.map do |data|
              Google::Apis::SheetsV4::ValueRange.new(
                range: data[:range],
                values: data[:values]
              )
            end,
            value_input_option: 'USER_ENTERED'
          )
          
          @sheets_service.batch_update_values(
            @spreadsheet_id,
            batch_update_request
          )
          
          puts "[SheetManager] 배치 업데이트 완료: #{updates_hash.keys.join(', ')}"

          # if update successful, invalidate cache
          invalidate_cache

          return true
        end

        false
      rescue => e
        puts "[SheetManager] 배치 업데이트 오류: #{e.message}"
        puts e.backtrace[0..3]
        false
      end
    end
  end
end
