require 'google/apis/sheets_v4'
require 'googleauth'

class SheetManager
  def initialize(sheet_id, credentials_path)
    @sheet_id = sheet_id
    @service = Google::Apis::SheetsV4::SheetsService.new
    @service.authorization = Google::Auth::ServiceAccountCredentials.make_creds(
      json_key_io: File.open(credentials_path),
      scope: Google::Apis::SheetsV4::AUTH_SPREADSHEETS
    )
  end

  def read_values(range)
    result = @service.get_spreadsheet_values(@sheet_id, range)
    result.values
  rescue => e
    puts "Error reading values: #{e.message}"
    nil
  end

  def update_values(range, values)
    value_range = Google::Apis::SheetsV4::ValueRange.new(values: values)
    @service.update_spreadsheet_value(
      @sheet_id,
      range,
      value_range,
      value_input_option: 'USER_ENTERED'
    )
  rescue => e
    puts "Error updating values: #{e.message}"
  end

  def append_values(range, values)
    value_range = Google::Apis::SheetsV4::ValueRange.new(values: values)
    @service.append_spreadsheet_value(
      @sheet_id,
      range,
      value_range,
      value_input_option: 'USER_ENTERED'
    )
  rescue => e
    puts "Error appending values: #{e.message}"
  end

  def find_user(user_id)
    values = read_values("사용자!A:J")
    return nil unless values
    
    headers = values[0]
    values.each_with_index do |row, index|
      next if index == 0
      if row[0]&.gsub('@', '') == user_id.gsub('@', '')
        result = {}
        headers.each_with_index { |header, col_index| result[header] = row[col_index] }
        result['_row'] = index + 1
        return result
      end
    end
    nil
  end

  def get_stat(user_id, stat_name)
    user = find_user(user_id)
    return nil unless user
    user[stat_name]
  end

  def update_stat(user_id, stat_name, value)
    user = find_user(user_id)
    return unless user
    
    values = read_values("사용자!A1:Z1")
    headers = values[0]
    col_index = headers.index(stat_name)
    return unless col_index
    
    col_letter = number_to_column_letter(col_index + 1)
    range = "사용자!#{col_letter}#{user['_row']}"
    update_values(range, [[value]])
  end

  def find_investigation_data(target, kind)
    values = read_values("조사!A:E")
    return nil unless values && !values.empty?
    
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

  def update_cell(row, col, value)
    column_letter = number_to_column_letter(col)
    range = "#{@title}!#{column_letter}#{row}"
    @sheet_manager.update_values(range, [[value]])
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
end
