# sheet_manager.rb
require 'google/apis/sheets_v4'

class SheetManager
  def initialize(sheets_service, sheet_id)
    @service = sheets_service
    @sheet_id = sheet_id
    @worksheets_cache = {}
  end

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

  def worksheet_by_title(title)
    @worksheets_cache[title] ||= WorksheetWrapper.new(self, title)
  end

  def worksheet(title)
    worksheet_by_title(title)
  end

  def get_stat(user_id, column_name)
    clean_user_id = user_id.gsub('@', '')
    
    values = read_values("사용자!A:Z")
    return nil if values.nil? || values.empty?
    
    headers = values[0]
    id_index = headers.index("ID")
    col_index = headers.index(column_name)
    return nil unless id_index && col_index
    
    values.each_with_index do |row, index|
      next if index == 0
      row_id = (row[id_index] || "").gsub('@', '')
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
    id_index = headers.index("ID")
    col_index = headers.index(column_name)
    return false unless id_index && col_index
    
    values.each_with_index do |row, index|
      next if index == 0
      row_id = (row[id_index] || "").gsub('@', '')
      if row_id == clean_user_id
        col_letter = number_to_column_letter(col_index + 1)
        range = "사용자!#{col_letter}#{index + 1}"
        update_values(range, [[value]])
        return true
      end
    end
    false
  end

  def find_user(user_id)
    clean_user_id = user_id.gsub('@', '')
    
    values = read_values("사용자!A:K")
    return nil if values.nil? || values.empty?
    
    headers = values[0]
    
    values.each_with_index do |row, index|
      next if index == 0
      row_id = (row[0] || "").gsub('@', '')
      if row_id == clean_user_id
        return {
          sheet_row: index + 1,
          id: row[0],
          name: row[1],
          galleons: row[2].to_i,
          items: row[3] || "",
          last_bet_date: row[4],
          house: row[5],
          hp: row[6].to_i,
          attack: row[7].to_i,
          attendance_date: row[8],
          last_tarot_date: row[9],
          house_score: row[10].to_i
        }
      end
    end
    nil
  end

  def update_user(user_id, data = {})
    user = find_user(user_id)
    return false unless user
    
    sheet_row = user[:sheet_row]
    
    row_data = [
      data[:id] || user[:id],
      data[:name] || user[:name],
      data[:galleons] || user[:galleons],
      data[:items] || user[:items],
      data[:last_bet_date] || user[:last_bet_date],
      data[:house] || user[:house],
      data[:hp] || user[:hp],
      data[:attack] || user[:attack],
      data[:attendance_date] || user[:attendance_date],
      data[:last_tarot_date] || user[:last_tarot_date],
      data[:house_score] || user[:house_score]
    ]
    
    range = "사용자!A#{sheet_row}:K#{sheet_row}"
    puts "[DEBUG] 전체 행 업데이트: #{range}"
    
    result = update_values(range, [row_data])
    result != nil
  end

  def increment_user_value(user_id, field, amount)
    user = find_user(user_id)
    return false unless user
    
    puts "[DEBUG] #{field} +#{amount} for #{user_id}"
    
    case field
    when "갈레온"
      update_user(user_id, galleons: user[:galleons] + amount)
    when "개별 기숙사 점수"
      update_user(user_id, house_score: user[:house_score] + amount)
    else
      false
    end
  end

  def set_user_value(user_id, field, value)
    user = find_user(user_id)
    return false unless user
    
    puts "[DEBUG] #{field} = #{value} for #{user_id}"
    
    case field
    when "출석날짜"
      update_user(user_id, attendance_date: value)
    when "과제날짜"
      update_user(user_id, last_bet_date: value)
    else
      false
    end
  end

  def add_user_row(user_data)
    append_values("사용자!A:K", [user_data])
  end

  def find_item(item_name)
    values = read_values("아이템!A:E")
    return nil if values.nil? || values.empty?
    
    headers = values[0]
    
    values.each_with_index do |row, index|
      next if index == 0
      if row[0] == item_name
        return {
          name: row[0],
          description: row[1],
          price: row[2].to_i,
          for_sale: row[3],
          category: row[4]
        }
      end
    end
    nil
  end

  def find_investigation(target, kind)
    values = read_values("조사!A:Z")
    return nil if values.nil? || values.empty?
    
    headers = values[0]
    values.each_with_index do |row, index|
      next if index == 0
      if row[0] == target
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

  def []=(row, col, value)
    load_data
    while @data.length < row
      @data << []
    end
    while @data[row-1].length < col
      @data[row-1] << ""
    end
    
    @data[row-1][col-1] = value
    
    cell_range = "#{@title}!#{column_letter(col)}#{row}"
    @sheet_manager.update_values(cell_range, [[value]])
  end

  def update_cell(row, col, value)
    column_letter = number_to_column_letter(col)
    range = "#{@title}!#{column_letter}#{row}"
    @sheet_manager.update_values(range, [[value]])
    load_data
  end

  def insert_rows(at_row, rows_data)
    puts "[DEBUG] WorksheetWrapper.insert_rows 호출됨: #{rows_data.inspect}"
    range = "#{@title}!A#{at_row}"
    @sheet_manager.append_values(range, rows_data)
    load_data
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

  def column_letter(col_num)
    result = ""
    while col_num > 0
      col_num -= 1
      result = ((col_num % 26) + 65).chr + result
      col_num /= 26
    end
    result
  end
end
