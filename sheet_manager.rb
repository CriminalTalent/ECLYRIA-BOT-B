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
    @service.get_spreadsheet_values(@sheet_id, range).values
  rescue
    nil
  end

  def update_values(range, values)
    range_obj = Google::Apis::SheetsV4::ValueRange.new(values: values)
    @service.update_spreadsheet_value(@sheet_id, range, range_obj, value_input_option: 'USER_ENTERED')
  end

  # user_id 행을 찾아 field 열을 :add 또는 :set
  def update_stat(*args, **kwargs)
    if kwargs.empty?
      # 위치 인자 형태: (user_id, field, value [, mode] [, sheet])
      case args.length
      when 3
        user_id, field, value = args
        mode  = :add
        sheet = '사용자'
      when 4
        user_id, field, value, fourth = args
        if fourth.is_a?(Symbol) || %w[add set].include?(fourth.to_s)
          mode  = fourth.to_sym
          sheet = '사용자'
        else
          mode  = :add
          sheet = fourth.to_s
        end
      when 5
        user_id, field, value, mode, sheet = args
        mode = mode.to_sym
      else
        raise ArgumentError, "update_stat expects (user_id, field, value [, mode] [, sheet]) or keyword args"
      end
      _update_stat_core(user_id: user_id, field: field, value: value, mode: mode, sheet: sheet)
    else
      # 키워드 인자 형태: user_id:, field:, value:, (mode:, sheet:)
      kwargs[:mode]  = (kwargs[:mode]  || :add).to_sym
      kwargs[:sheet] = (kwargs[:sheet] || '사용자').to_s
      _update_stat_core(**kwargs)
    end
  end

  def a1_address(row_num, col_num, sheet)
    col = ''
    n = col_num
    while n > 0
      n, r = (n - 1).divmod(26)
      col.prepend((65 + r).chr)
    end
    "#{sheet}!#{col}#{row_num}"
  end

  def find_row_index_by_user_id(data, headers, user_id)
    candidates = %w[user_id user acct account 계정 사용자 아이디]
    key_col = candidates.map { |k| headers.index(k) }.compact.first
    return nil if key_col.nil?
    (1...data.length).each do |r|
      return r if data[r][key_col].to_s.strip.downcase == user_id.to_s.strip.downcase
    end
    nil
  end


  def append_values(range, values)
    range_obj = Google::Apis::SheetsV4::ValueRange.new(values: values)
    @service.append_spreadsheet_value(@sheet_id, range, range_obj, value_input_option: 'USER_ENTERED')
  end

  # === 사용자 ===
  def find_user(user_id)
    rows = read_values("사용자!A:J")
    return nil unless rows && rows.any?
    headers = rows[0]
    key_col = 0 # A열 = 사용자 ID

    target = normalize_user_id(user_id)
    rows.each_with_index do |r, i|
      next if i == 0
      cell = r[key_col]
      next if cell.nil? || cell.empty?
      if normalize_user_id(cell) == target
        h = {}
        headers.each_with_index { |hname, j| h[hname] = r[j] }
        h["_row"] = i + 1
        return h
      end
    end
    nil
  end

  # === 조사 기능 ===
  def is_location?(target)
    rows = read_values("조사!A:A")
    rows.flatten.compact.include?(target)
  end

  def available_locations
    rows = read_values("조사!A:A")
    rows.flatten.compact.uniq
  end

  def find_details_in_location(location)
    rows = read_values("조사!A:B")
    rows.select { |r| r[0] == location && r[1] && !r[1].empty? }.map { |r| r[1] }.uniq
  end

  def find_investigation_entry(target, kind)
    rows = read_values("조사!A:G")
    return nil unless rows && !rows.empty?
    headers = rows[0]
    rows.each_with_index do |r, i|
      next if i == 0
      if r[1] == target && r[3] == kind
        data = {}
        headers.each_with_index { |h, j| data[h] = r[j] }
        return data
      end
    end
    nil
  end

  # === 조사상태 ===
  def get_investigation_state(user_id)
    rows = read_values("조사상태!A:C")
    headers = rows[0]
    record = rows.find { |r| r[0] == user_id }
    return {} unless record
    Hash[headers.zip(record)]
  end

  def update_investigation_state(user_id, state, location)
    rows = read_values("조사상태!A:C")
    idx = rows.find_index { |r| r[0] == user_id }
    return unless idx
    update_values("조사상태!B#{idx+1}:C#{idx+1}", [[state, location]])
  end

  # === 로그 ===
  def log_investigation(user_id, location, target, kind, success, result)
    time = Time.now.strftime('%Y-%m-%d %H:%M')
    outcome = success ? "성공" : "실패"
    append_values("조사로그!A:G", [[time, user_id, location, target, kind, outcome, result]])
  end

  private

  def _update_stat_core(user_id:, field:, value:, mode:, sheet:)
    range = "#{sheet}!A:Z"
    rows  = read_values(range) || []   # ← read_values 사용
    raise "빈 시트(#{sheet})" if rows.empty?

    headers = rows.first.map(&:to_s)
    row_idx = find_row_index_by_user_id(rows, headers, user_id)  # ← rows 사용
    raise "user_id=#{user_id} 행 없음(#{sheet})" if row_idx.nil?

    col_idx = headers.index(field.to_s)
    raise "필드 '#{field}' 없음. headers=#{headers.inspect}" if col_idx.nil?

    current_str = rows[row_idx][col_idx].to_s.strip
    current_num = (current_str =~ /\A-?\d+(\.\d+)?\z/) ? current_str.to_f : 0.0

    new_value = case mode
                when :add then current_num + value.to_f
                when :set then value
                else raise "지원하지 않는 mode: #{mode}"
                end

    a1 = a1_address(row_idx + 1, col_idx + 1, sheet)
    update_values(a1, [[new_value]])  # 단일 셀 업데이트
    true
  end


  def a1_address(row_num, col_num, sheet)
    col = ''
    n = col_num
    while n > 0
      n, r = (n - 1).divmod(26)
      col.prepend((65 + r).chr)
    end
    "#{sheet}!#{col}#{row_num}"
  end

  def normalize_user_id(s)
    return '' if s.nil?
    s = s.to_s.strip
    # 제어문자 제거(보이지 않는 문자 때문에 매칭이 어긋나는 경우가 있음)
    s = s.gsub(/\p{Cf}/, '')
    s = s.sub(/\A@+/, '')  # 맨 앞 @ 제거
    # name@server 형태면 name만, 그 외엔 전체
    first = s.include?('@') ? s.split('@', 2).first : s
    first.nil? ? '' : first.downcase
  end


  def find_row_index_by_user_id(rows, headers, user_id)
    norm = normalize_user_id(user_id)

    # 1) 헤더에서 후보 키 찾기
    candidates = %w[user_id user acct account 계정 사용자 아이디]
    key_col = candidates.map { |k| headers.index(k) }.compact.first

    # 2) 없으면 A열(첫 열)로 폴백
    key_col ||= 0

    # 3) 데이터 구간 순회 (1행은 헤더)
    (1...rows.length).each do |r|
      cell = rows[r][key_col]
      next if cell.nil?
      cell_norm = normalize_user_id(cell)
      return r if cell_norm == norm
    end

    nil
  end

end
