# core/sheet_manager.rb

module SheetManager
  module_function

  def worksheet(name)
    @sheet.worksheet(name)
  end

  def set_sheet(sheet)
    @sheet = sheet
  end

  def get_stat(user_id, column_name)
    sheet = worksheet("사용자")
    headers = sheet.rows[0]
    id_index = headers.index("ID")
    col_index = headers.index(column_name)
    return nil if id_index.nil? || col_index.nil?

    row = sheet.rows.find { |r| r[id_index] == "@#{user_id}" }
    return nil unless row

    row[col_index]
  end

  def set_stat(user_id, column_name, value)
    sheet = worksheet("사용자")
    headers = sheet.rows[0]
    id_index = headers.index("ID")
    col_index = headers.index(column_name)
    return unless id_index && col_index

    row_num = sheet.rows.find_index { |r| r[id_index] == "@#{user_id}" }
    return unless row_num

    sheet.update_cell(row_num + 1, col_index + 1, value)  # row/col는 1-based
  end

  def get_row(user_id)
    sheet = worksheet("사용자")
    headers = sheet.rows[0]
    id_index = headers.index("ID")
    return nil unless id_index

    row = sheet.rows.find { |r| r[id_index] == "@#{user_id}" }
    return nil unless row

    Hash[headers.zip(row)]
  end

  def update_row(user_id, data_hash)
    sheet = worksheet("사용자")
    headers = sheet.rows[0]
    id_index = headers.index("ID")
    return unless id_index

    row_num = sheet.rows.find_index { |r| r[id_index] == "@#{user_id}" }
    return unless row_num

    data_hash.each do |key, value|
      col = headers.index(key)
      next unless col
      sheet.update_cell(row_num + 1, col + 1, value)
    end
  end
end

