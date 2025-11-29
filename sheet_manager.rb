require 'google/apis/sheets_v4'
require 'googleauth'

class SheetManager
  CACHE_DURATION = 5 # 캐시 유효 시간 (초) - API 호출 최소화

  def initialize(sheet_id, credentials_path)
    @sheet_id = sheet_id
    @service = Google::Apis::SheetsV4::SheetsService.new
    @service.authorization = Google::Auth::ServiceAccountCredentials.make_creds(
      json_key_io: File.open(credentials_path),
      scope: Google::Apis::SheetsV4::AUTH_SPREADSHEETS
    )

    # 캐시 저장소
    @cache = {}
    @cache_time = {}

    puts "[SheetManager] 캐시 시스템 활성화 (유효시간: #{CACHE_DURATION}초)"
  end

  # 캐시를 사용하는 read_values
  def read_values(range)
    # 캐시 확인
    if @cache[range] && @cache_time[range]
      elapsed = Time.now - @cache_time[range]
      if elapsed < CACHE_DURATION
        # puts "[캐시 히트] #{range} (#{elapsed.round(2)}초 전)"
        return @cache[range]
      end
    end

    # 캐시 미스 - API 호출
    # puts "[API 호출] #{range}"
    result = @service.get_spreadsheet_values(@sheet_id, range).values

    # 캐시 저장
    @cache[range] = result
    @cache_time[range] = Time.now

    result
  rescue => e
    puts "[에러] read_values 실패: #{e.message}"
    nil
  end

  # 캐시 무효화 (데이터 변경 시 호출)
  def invalidate_cache(range = nil)
    if range
      @cache.delete(range)
      @cache_time.delete(range)
      # puts "[캐시 무효화] #{range}"
    else
      @cache.clear
      @cache_time.clear
      # puts "[캐시 전체 무효화]"
    end
  end

  def update_values(range, values)
    range_obj = Google::Apis::SheetsV4::ValueRange.new(values: values)
    result = @service.update_spreadsheet_value(@sheet_id, range, range_obj, value_input_option: 'USER_ENTERED')

    # 업데이트 후 관련 캐시 무효화
    sheet_name = range.split('!').first
    invalidate_cache("#{sheet_name}!A:Z")

    result
  end

  def append_values(range, values)
    range_obj = Google::Apis::SheetsV4::ValueRange.new(values: values)
    result = @service.append_spreadsheet_value(@sheet_id, range, range_obj, value_input_option: 'USER_ENTERED')

    # 추가 후 관련 캐시 무효화
    sheet_name = range.split('!').first
    invalidate_cache("#{sheet_name}!A:Z")

    result
  end

  # === 사용자 찾기 (캐시 활용) ===
  def find_user(user_id)
    rows = read_values("스탯!A:Z")
    return nil unless rows

    headers = rows[0]

    rows.each_with_index do |r, i|
      next if i == 0
      if r[0]&.gsub('@', '') == user_id.gsub('@', '')
        h = convert_user_row(headers, r)
        h[:_row] = i + 1
        h["_row"] = i + 1
        return h
      end
    end
    nil
  end

  # === 사용자 업데이트 ===
  def update_user(user_id, updates)
    rows = read_values("스탯!A:Z")
    return false unless rows

    headers = rows[0]

    rows.each_with_index do |row, idx|
      next if idx == 0
      next unless row[0]&.gsub('@', '') == user_id.gsub('@', '')

      updates.each do |key, value|
        # 영어 키를 한글 헤더로 변환
        header_name = case key.to_sym
                      # 전투 스탯
                      when :id then "ID"
                      when :name then "이름"
                      when :hp then "HP"
                      when :agility then "민첩"
                      when :luck then "행운"
                      when :attack then "공격"
                      when :defense then "방어"

                      # 상점봇용
                      when :galleons then "갈레온"
                      when :items then "아이템"
                      when :last_bet_date then "마지막베팅날짜"
                      when :house then "기숙사"
                      when :attack_power then "공격력"
                      when :attendance_date then "출석날짜"
                      when :last_tarot_date then "마지막타로날짜"
                      when :house_points then "기숙사점수"
                      when :bet_count then "마지막베팅횟수"

                      else key.to_s
                      end

        col = headers.index(header_name)
        next unless col
        row[col] = value
      end

      update_values("스탯!A#{idx+1}:Z#{idx+1}", [row])
      return true
    end
    false
  end

  # === 한글 헤더 → 영어 키 변환 (양방향) ===
  def convert_user_row(headers, row)
    data = {}
    headers.each_with_index do |h, i|
      # 한글 키 그대로 저장 (하위 호환)
      data[h] = row[i]

      # 영어 심볼 키 추가
      key = case h
            # 전투 스탯
            when "ID" then :id
            when "이름" then :name
            when "HP" then :hp
            when "민첩" then :agility
            when "행운" then :luck
            when "공격" then :attack
            when "방어" then :defense

            # 상점봇용
            when "사용자 ID" then :id
            when "갈레온" then :galleons
            when "아이템" then :items
            when "마지막베팅날짜" then :last_bet_date
            when "기숙사" then :house
            when "공격력" then :attack_power
            when "출석날짜" then :attendance_date
            when "마지막타로날짜" then :last_tarot_date
            when "기숙사점수" then :house_points
            when "마지막베팅횟수" then :bet_count

            else nil
            end

      data[key] = row[i] if key
    end
    data
  end

  # === 조사 기능 ===
  def is_location?(target)
    rows = read_values("조사!A:A")
    return false unless rows
    rows.flatten.compact.include?(target)
  end

  def available_locations
    rows = read_values("조사!A:A")
    return [] unless rows
    rows.flatten.compact.uniq
  end

  def find_details_in_location(location)
    rows = read_values("조사!A:B")
    return [] unless rows
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
    rows = read_values("조사상태!A:Z")
    return {} unless rows
    headers = rows[0]
    record = rows.find { |r| r[0] == user_id }
    return {} unless record
    Hash[headers.zip(record)]
  end

  def update_investigation_state(user_id, state, location)
    rows = read_values("조사상태!A:Z")
    return unless rows
    idx = rows.find_index { |r| r[0] == user_id }
    return unless idx
    update_values("조사상태!B#{idx+1}:C#{idx+1}", [[state, location]])
  end

  def upsert_investigation_state(user_id, state, location)
    rows = read_values("조사상태!A:Z")
    return unless rows

    idx = rows.find_index { |r| r[0] == user_id }

    if idx
      # 기존 레코드 업데이트
      update_values("조사상태!B#{idx+1}:C#{idx+1}", [[state, location]])
    else
      # 새 레코드 추가
      append_values("조사상태!A:Z", [[user_id, state, location, "", 3, ""]])
    end
  end

  # === 협력상태 관련 ===
  def set_status_effect(user_id, effect)
    rows = read_values("조사상태!A:Z")
    return unless rows

    headers = rows[0]
    effect_col = headers.index("협력상태")
    return unless effect_col

    rows.each_with_index do |row, idx|
      next if idx == 0
      if row[0] == user_id
        row[effect_col] = effect
        update_values("조사상태!A#{idx+1}:Z#{idx+1}", [row])
        return
      end
    end
  end

  def clear_status_effect(user_id)
    set_status_effect(user_id, "")
  end

  # === 이동 포인트 관련 ===
  def update_move_points(user_id, points)
    rows = read_values("조사상태!A:Z")
    return unless rows

    headers = rows[0]
    points_col = headers.index("이동포인트")
    return unless points_col

    rows.each_with_index do |row, idx|
      next if idx == 0
      if row[0] == user_id
        row[points_col] = points
        update_values("조사상태!A#{idx+1}:Z#{idx+1}", [row])
        return
      end
    end
  end

  # === 위치 관련 ===
  def location_overview_outputs(location)
    rows = read_values("조사!A:G")
    return [] unless rows && !rows.empty?

    rows.select { |r| r[0] == location && r[2] && !r[2].empty? }.map { |r| r[2] }
  end

  def detail_candidates(location)
    rows = read_values("조사!A:G")  # 전체 열 가져오기
    puts "[디버그] detail_candidates: location='#{location}'"
    return [] unless rows
    
    current_location = nil
    details = []
    
    rows.each_with_index do |r, i|
      next if i == 0  # 헤더 스킵
      
      # A열에 값이 있으면 현재 위치 업데이트
      if r[0] && !r[0].empty?
        current_location = r[0]
      end
      
      # 현재 위치가 찾는 위치이고, B열(세부조사)에 값이 있으면 추가
      if current_location == location && r[1] && !r[1].empty?
        details << r[1]
      end
    end
    
    puts "[디버그] detail_candidates 결과: #{details.uniq.inspect}"
    details.uniq
  end

  # === 로그 ===
  def log_investigation(user_id, location, target, kind, success, result)
    time = Time.now.strftime('%Y-%m-%d %H:%M')
    outcome = success ? "성공" : "실패"
    append_values("조사로그!A:G", [[time, user_id, location, target, kind, outcome, result]])
  end
end
