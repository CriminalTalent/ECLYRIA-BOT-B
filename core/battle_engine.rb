# core/battle_engine.rb
require_relative 'battle_state'

class BattleEngine
  def initialize(mastodon_client, sheet_manager)
    @mastodon_client = mastodon_client
    @sheet_manager = sheet_manager

    # 전투 상태를 엔진이 들고 있는 방식(최소 기능)
    @battles = {}
  end

  # --------------------
  # 공통 유틸
  # --------------------
  def normalize_id(raw)
    return nil if raw.nil?
    s = raw.to_s.strip
    s = s.sub(/\A@/, '')
    s = s.split('@', 2)[0]     # "user@domain" -> "user"
    s = s.gsub(/\s+/, '')
    s.downcase
  end

  def find_user_safe(raw_id)
    uid = normalize_id(raw_id)
    return nil if uid.nil? || uid.empty?
    @sheet_manager.find_user(uid)
  end

  # 아이템 문자열에서 item_name 1개 차감
  # 지원: "중형물약", "중형물약x2", "중형물약:2", "중형물약(2)"
  def consume_item_one(raw_user_id, item_name)
    user_id = normalize_id(raw_user_id)
    user = find_user_safe(user_id)
    return [false, "등록되지 않은 사용자입니다."] unless user

    items_str = (user["아이템"] || "").to_s.strip
    items = items_str.split(',').map(&:strip).reject(&:empty?)

    idx = items.find_index { |it| it.start_with?(item_name) }
    return [false, "#{item_name}을(를) 보유하고 있지 않습니다."] unless idx

    token = items[idx]
    name, qty = parse_item_token(token)
    if qty <= 1
      items.delete_at(idx)
    else
      items[idx] = "#{name}x#{qty - 1}"
    end

    new_items_str = items.join(', ')
    ok = @sheet_manager.update_user_items(user_id, new_items_str)
    return [false, "시트 업데이트 실패"] unless ok

    [true, "#{item_name} 사용 완료"]
  end

  def parse_item_token(token)
    s = token.to_s.strip
    # namex2 / name:2 / name(2)
    if s =~ /\A(.+?)[x:](\d+)\z/i
      [Regexp.last_match(1).strip, Regexp.last_match(2).to_i]
    elsif s =~ /\A(.+?)\((\d+)\)\z/
      [Regexp.last_match(1).strip, Regexp.last_match(2).to_i]
    else
      [s, 1]
    end
  end

  # ==========================================================
  # ✅ 전투 개설 메서드(이번 에러의 직접 해결책)
  # ==========================================================

  # 1:1 전투 개설
  # participants: ["misen","ocellio"]
  def start_1v1(thread_id, participants)
    participants = Array(participants).map { |x| normalize_id(x) }.reject(&:empty?)
    return "❌ 참가자가 2명이 아닙니다." unless participants.size == 2

    missing = participants.reject { |uid| @sheet_manager.find_user(uid) }
    return "❌ 등록되지 않은 계정: #{missing.join(', ')}" if missing.any?

    state = build_state(thread_id, participants, mode: '1v1')
    @battles[thread_id.to_s] = state

    "✅ 1:1 전투가 개설되었습니다.\n" \
    "참가: @#{participants[0]} vs @#{participants[1]}"
  end

  # 다인전투 개설 (2:2 / 4:4 / 자유 인원)
  # participants: ["misen","ocellio","riley_barnes","rasxix",...]
  def start_multi(thread_id, participants)
    participants = Array(participants).map { |x| normalize_id(x) }.reject(&:empty?).uniq
    return "❌ 참가자가 3명 이상 필요합니다." unless participants.size >= 3

    missing = participants.reject { |uid| @sheet_manager.find_user(uid) }
    return "❌ 등록되지 않은 계정: #{missing.join(', ')}" if missing.any?

    state = build_state(thread_id, participants, mode: 'multi')
    @battles[thread_id.to_s] = state

    "✅ 다인전투가 개설되었습니다.\n" \
    "참가: #{participants.map { |u| "@#{u}" }.join(' ')}"
  end

  # start_group도 같은 의미로 지원(파서 호환용)
  def start_group(thread_id, participants)
    start_multi(thread_id, participants)
  end

  # start_battle도 같은 의미로 지원(파서 호환용)
  def start_battle(thread_id, participants)
    if Array(participants).size == 2
      start_1v1(thread_id, participants)
    else
      start_multi(thread_id, participants)
    end
  end

  # 현재 전투 상태 조회(추후 공격/방어 커맨드에서 사용)
  def get_battle(thread_id)
    @battles[thread_id.to_s]
  end

  private

  # BattleState 생성자가 어떤 형태든 최대한 안전하게 생성
  def build_state(thread_id, participants, mode:)
    # 1) BattleState.new(thread_id, participants, mode) 형태 시도
    begin
      return BattleState.new(thread_id, participants, mode)
    rescue
    end

    # 2) BattleState.new(hash) 형태 시도
    begin
      return BattleState.new({
        "thread_id" => thread_id.to_s,
        "participants" => participants,
        "mode" => mode,
        "created_at" => Time.now.to_i
      })
    rescue
    end

    # 3) 기본 생성 + setter가 있으면 채우기
    begin
      st = BattleState.new
      st.thread_id = thread_id.to_s if st.respond_to?(:thread_id=)
      st.participants = participants if st.respond_to?(:participants=)
      st.mode = mode if st.respond_to?(:mode=)
      return st
    rescue
    end

    # 4) 최후: 해시로라도 저장
    {
      "thread_id" => thread_id.to_s,
      "participants" => participants,
      "mode" => mode,
      "created_at" => Time.now.to_i
    }
  end
end
