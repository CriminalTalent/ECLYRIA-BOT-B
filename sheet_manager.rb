# sheet_manager.rb - 통합 버전 (상점봇, 교수봇, 전투봇 모두 호환)
require 'google/apis/sheets_v4'

class SheetManager
  def initialize(sheets_service, spreadsheet_id)
    @service = sheets_service
    @spreadsheet_id = spreadsheet_id
    @sheet_id = spreadsheet_id # 호환성 위한 별칭
    @worksheets_cache = {}
  end

  # ==========================================
  # 기본 Google Sheets API v4 메서드
  # ==========================================
  
  def read_values(range)
    @service.get_spreadsheet_values(@spreadsheet_id, range).values
  rescue => e
    puts "시트 읽기 오류: #{e.message}"
    []
  end

  def update_values(range, values)
    puts "[DEBUG] 업데이트 시도: 범위=#{range}, 값=#{values.inspect}"
    value_range = Google::Apis::SheetsV4::ValueRange.new(values: values)
    result = @service.update_spreadsheet_value(@spreadsheet_id, range, value_range, value_input_option: 'USER_ENTERED')
    puts "[DEBUG] 업데이트 결과: #{result.updated_cells}개 셀 업데이트됨"
    result
  rescue => e
    puts "시트 쓰기 오류: #{e.message}"
    puts e.backtrace.first(3)
    nil
  end

  def append_values(range, values)
    value_range = Google::Apis::SheetsV4::ValueRange.new(values: values)
    result = @service.append_spreadsheet_value(@spreadsheet_id, range, value_range, value_input_option: 'USER_ENTERED')
    result
  rescue => e
    puts "시트 추가 오류: #{e.message}"
    nil
  end

  # ==========================================
  # 상점봇 전용 메서드
  # ==========================================
  
  def get_player(user_id)
    # user_id에서 @ 제거 (일관성을 위해)
    clean_user_id = user_id.gsub('@', '')
    
    range = "사용자!A:K"
    values = read_values(range)
    return nil if values.nil? || values.empty?
    
    values.each_with_index do |row, index|
      next if index == 0 # 헤더 스킵
      # ID 필드에서 @ 제거해서 비교
      row_id = (row[0] || "").gsub('@', '')
      if row_id == clean_user_id
        return {
          row: index,  # 0-based index (update_player에서 +1 처리)
          id: clean_user_id,
          name: row[1],
          galleons: (row[2] || 0).to_i,
          items: (row[3] || "").to_s,
          memo: row[4],
          house: row[5],
          last_bet_date: row[6],
          bet_count: (row[7] || 0).to_i,
          attendance_date: row[8],
          last_tarot_date: row[9],
          house_score: (row[10] || 0).to_i
        }
      end
    end
    nil
  end

  def update_player(player)
    row = player[:row] + 1  # Google Sheets는 1-based index
    range = "사용자!A#{row}:K#{row}"
    
    values = [
      player[:id],
      player[:name],
      player[:galleons],
      player[:items],
      player[:memo],
      player[:house],
      player[:last_bet_date],
      player[:bet_count],
      player[:attendance_date],
      player[:last_tarot_date],
      player[:house_score]
    ]
    
    value_range = Google::Apis::SheetsV4::ValueRange.new
    value_range.values = [values]
    
    begin
      result = @service.update_spreadsheet_value(
        @spreadsheet_id,
        range,
        value_range,
        value_input_option: 'RAW'
      )
      puts "[DEBUG] 플레이어 업데이트 완료: #{player[:id]}, 갈레온: #{player[:galleons]}"
      result
    rescue => e
      puts "플레이어 업데이트 오류: #{e.message}"
      nil
    end
  end

  def get_item(item_name)
    range = "아이템!A:I"
    values = read_values(range)
    return nil if values.nil? || values.empty?
    
    values.each_with_index do |row, index|
      next if index == 0 # 헤더 스킵
      if row[0] == item_name
        return {
          row: index,
          name: item_name,
          price: (row[1] || 0).to_i,
          description: row[3],
          purchasable: (row[4] || "").to_s.strip.upcase == 'TRUE',
          transferable: (row[5] || "").to_s.strip.upcase == 'TRUE',
          usable: (row[6] || "").to_s.strip.upcase == 'TRUE',
          effect: row[7],
          consumable: (row[8] || "").to_s.strip.upcase == 'TRUE'
        }
      end
    end
    nil
  end

  # ==========================================
  # 교수봇 전용 메서드
  # ==========================================
  
  def find_user(user_id)
    # get_player와 동일하지만 교수봇 호환을 위한 별칭
    get_player(user_id)
  end

  def increment_user_value(user_id, field_name, increment)
    user = get_player(user_id)
    return false unless user
    
    # 필드명을 심볼로 변환
    field_map = {
      "갈레온" => :galleons,
      "개별 기숙사 점수" => :house_score
    }
    
    field_sym = field_map[field_name] || field_name.to_sym
    current_value = user[field_sym].to_i
    user[field_sym] = current_value + increment
    
    update_player(user)
  end

  def set_user_value(user_id, field_name, value)
    user = get_player(user_id)
    return false unless user
    
    field_map = {
      "출석날짜" => :attendance_date,
      "과제날짜" => :last_bet_date  # 임시로 last_bet_date 사용
    }
    
    field_sym = field_map[field_name] || field_name.to_sym
    user[field_sym] = value
    
    update_player(user)
  end

  def create_user(user_id, name, initial_galleons = 20)
    # 새 사용자 추가
    values = [[user_id, name, initial_galleons, "", "", "", "", "", "", "", 0]]
    append_values("사용자!A:K", values)
  end

  # ==========================================
  # 전투봇 전용 메서드
  # ==========================================
  
  def get_stat(user_id, column_name)
    clean_user_id = user_id.gsub('@', '')
    
    values = read_values("사용자!A:Z")
    return nil if values.nil? || values.empty?
    
    headers = values[0]
    col_index = headers.index(column_name)
    return nil unless col_index
    
    values.each_with_index do |row, index|
      next if index == 0
      row_id = (row[0] || "").gsub('@', '')
      if row_id == clean_user_id
        return row[col_index]
      end
    end
    nil
  end

  def set_stat(user_id, column_name, value)
    clean_user_id = user_id.gsub('@', '')
    
    values = read_values("사용자!A:Z")
    return false if values.nil? || values.empty?
    
    headers = values[0]
    col_index = headers.index(column_name)
    return false unless col_index
    
    values.each_with_index do |row, index|
      next if index == 0
      row_id = (row[0] || "").gsub('@', '')
      if row_id == clean_user_id
        column_letter = number_to_column_letter(col_index + 1)
        range = "사용자!#{column_letter}#{index + 1}"
        update_values(range, [[value]])
        return true
      end
    end
    false
  end

  def get_investigation(target, kind)
    values = read_values("조사!A:Z")
    return nil if values.nil? || values.empty?
    
    headers = values[0]
    values.each_with_index do |row, index|
      next if index == 0
      if row[0] == target
        # "조사" 종류일 경우 "DM조사"도 허용
        if kind == "조사"
          if ["조사", "DM조사"].include?(row[1])
            result = {}
            headers.each_with_index { |header, col_index| result[header] = row[col_index] }
            return result
          end
        else
          if row[1] == kind
            result = {}
            headers.each_with_index { |header, col_index| result[header] = row[col_index] }
            return result
          end
        end
      end
    end
    nil
  end

  # ==========================================
  # 전투봇 워크시트 래퍼 (구 google_drive gem 호환)
  # ==========================================
  
  def worksheet_by_title(title)
    @worksheets_cache[title] ||= WorksheetWrapper.new(self, title)
  end
  
  def worksheet(title)
    worksheet_by_title(title)
  end

  # ==========================================
  # 기숙사 점수 관련 (교수봇, 상점봇 공통)
  # ==========================================
  
  def get_house_scores
    values = read_values("기숙사!A:B")
    return {} if values.nil? || values.empty?
    
    scores = {}
    values.each_with_index do |row, index|
      next if index == 0
      house_name = row[0]
      score = (row[1] || 0).to_i
      scores[house_name] = score if house_name
    end
    scores
  end

  def update_house_score(house_name, new_score)
    values = read_values("기숙사!A:B")
    return false if values.nil? || values.empty?
    
    values.each_with_index do |row, index|
      next if index == 0
      if row[0] == house_name
        range = "기숙사!B#{index + 1}"
        update_values(range, [[new_score]])
        return true
      end
    end
    false
  end

  # ==========================================
  # 유틸리티 메서드
  # ==========================================
  
  private

  def number_to_column_letter(col_num)
    result = ""
    while col_num > 0
      col_num -= 1
      result = ((col_num % 26) + 65).chr + result
      col_num /= 26
    end
    result
  end
end

# ==========================================
# WorksheetWrapper 클래스 (전투봇 구 API 호환용)
# ==========================================

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

  def save
    # 새로운 API에서는 즉시 저장되므로 별도 작업 불필요
    true
  end

  def num_rows
    load_data
    @data.length
  end

  def rows
    load_data
    @data
  end

  def [](row, col)
    load_data
    return nil if row < 1 || row > @data.length
    return nil if col < 1 || col > (@data[row-1]&.length || 0)
    @data[row-1][col-1]
  end

  def update_cell(row, col, value)
    column_letter = number_to_column_letter(col)
    range = "#{@title}!#{column_letter}#{row}"
    @sheet_manager.update_values(range, [[value]])
    load_data # 데이터 새로고침
  end

  private

  def number_to_column_letter(col_num)
    result = ""
    while col_num > 0
      col_num -= 1
      result = ((col_num % 26) + 65).chr + result
      col_num /= 26
    end
    result
  end
end
