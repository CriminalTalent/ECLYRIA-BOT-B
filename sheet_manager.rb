# sheet_manager.rb
require 'google/apis/sheets_v4'

class SheetManager
  def initialize(sheets_service, sheet_id)
    @service = sheets_service
    @sheet_id = sheet_id
    @worksheets_cache = {}
  end

  # 기존 API v4 메서드들
  def read_values(range)
    @service.get_spreadsheet_values(@sheet_id, range).values
  rescue => e
    puts "시트 읽기 오류: #{e.message}"
    []
  end

  def update_values(range, values)
    puts "[DEBUG] 업데이트 시도: 범위=#{range}, 값=#{values.inspect}"
    value_range = Google::Apis::SheetsV4::ValueRange.new(values: values)
    result = @service.update_spreadsheet_value(@sheet_id, range, value_range, value_input_option: 'USER_ENTERED')
    puts "[DEBUG] 업데이트 결과: #{result.updated_cells}개 셀 업데이트됨"
    result
  rescue => e
    puts "시트 쓰기 오류: #{e.message}"
    puts e.backtrace.first(3)
    nil
  end

  def append_values(range, values)
    puts "[DEBUG] 추가 시도: 범위=#{range}, 값=#{values.inspect}"
    value_range = Google::Apis::SheetsV4::ValueRange.new(values: values)
    result = @service.append_spreadsheet_value(@sheet_id, range, value_range, value_input_option: 'USER_ENTERED')
    puts "[DEBUG] 추가 결과: #{result.updated_rows}개 행 추가됨"
    result
  rescue => e
    puts "시트 추가 오류: #{e.message}"
    nil
  end

  # 구식 google_drive gem 호환 메서드들
  def worksheet_by_title(title)
    @worksheets_cache[title] ||= WorksheetWrapper.new(self, title)
  end

  def worksheet(title)
    worksheet_by_title(title)
  end

  # 전투봇 호환 메서드들
  def get_stat(user_id, column_name)
    # user_id에서 @ 제거 (전투봇은 @를 포함해서 전달할 수 있음)
    clean_user_id = user_id.gsub('@', '')
    
    values = read_values("사용자!A:Z")
    return nil if values.nil? || values.empty?
    
    headers = values[0]
    id_index = headers.index("ID")
    col_index = headers.index(column_name)
    return nil unless id_index && col_index
    
    values.each_with_index do |row, index|
      next if index == 0 # 헤더 스킵
      # ID 필드에서 @ 제거해서 비교
      row_id = (row[id_index] || "").gsub('@', '')
      if row_id == clean_user_id
        return row[col_index]
      end
    end
    nil
  end

  def set_stat(user_id, column_name, value)
    # user_id에서 @ 제거
    clean_user_id = user_id.gsub('@', '')
    
    values = read_values("사용자!A:Z")
    return false if values.nil? || values.empty?
    
    headers = values[0]
    id_index = headers.index("ID")
    col_index = headers.index(column_name)
    return false unless id_index && col_index
    
    values.each_with_index do |row, index|
      next if index == 0 # 헤더 스킵
      row_id = (row[index] || "").gsub('@', '')
      if row_id == clean_user_id
        # Google Sheets는 1-based index
        sheet_row = index + 1
        column_letter = number_to_column_letter(col_index + 1)
        range = "사용자!#{column_letter}#{sheet_row}"
        
        result = update_values(range, [[value]])
        return result != nil
      end
    end
    false
  end

  def find_user(user_id)
    clean_user_id = user_id.gsub('@', '')
    
    values = read_values("사용자!A:Z")
    return nil if values.nil? || values.empty?
    
    headers = values[0]
    values.each_with_index do |row, index|
      next if index == 0 # 헤더 스킵
      row_id = (row[0] || "").gsub('@', '')
      if row_id == clean_user_id
        user_data = {}
        headers.each_with_index do |header, col_index|
          user_data[header] = row[col_index]
        end
        return user_data
      end
    end
    nil
  end

  # 조사 시트 관련 메서드
  def find_investigation_data(target, kind)
    values = read_values("조사!A:Z")
    return nil if values.nil? || values.empty?
    
    headers = values[0]
    target_index = headers.index("대상")
    kind_index = headers.index("종류")
    return nil unless target_index && kind_index
    
    values.each_with_index do |row, index|
      next if index == 0 # 헤더 스킵
      if row[target_index] == target
        # 조사 종류가 "조사"일 경우 "DM조사"도 허용
        if kind == "조사"
          if ["조사", "DM조사"].include?(row[kind_index])
            result = {}
            headers.each_with_index { |header, col_index| result[header] = row[col_index] }
            return result
          end
        else
          if row[kind_index] == kind
            result = {}
            headers.each_with_index { |header, col_index| result[header] = row[col_index] }
            return result
          end
        end
      end
    end
    nil
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

# 구식 워크시트 객체를 흉내내는 래퍼 클래스 (전투봇 호환용)
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
    # Google Sheets API 호출
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
