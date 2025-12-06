# commands/coordinate_exploration_command.rb
# 좌표 기반 탐색 명령어 핸들러

require_relative '../core/coordinate_exploration_system'

class CoordinateExplorationCommand
  def initialize(mastodon_client, sheet_manager)
    @mastodon_client = mastodon_client
    @sheet_manager = sheet_manager
  end

  def handle_command(user_id, text, status)
    thread_id = get_thread_id(status)

    case text
    when /\[탐색시작\/(B[2-5])\]/i
      floor = $1.upcase
      start_exploration(user_id, floor, thread_id, status)

    when /\[협력탐색\/(B[2-5])\/((?:@\S+\/)*@\S+)\]/i
      floor = $1.upcase
      participants_text = $2
      participants = participants_text.split('/').map { |p| p.gsub('@', '').strip }.reject(&:empty?)
      start_coop_exploration(user_id, floor, participants, thread_id, status)

    when /\[이동\/([A-H][1-8])\]/i
      coord = $1.upcase
      move_to_coord(user_id, coord, thread_id, status)

    when /\[조사\/(.+)\]/i
      location_or_sub = $1.strip
      investigate_location_or_sub(user_id, location_or_sub, thread_id, status)

    when /\[심층조사\]/i
      start_deep_investigation_mode(user_id, thread_id, status)

    when /\[조사종료\]/i
      end_deep_investigation_mode(user_id, thread_id, status)

    when /\[맵보기\]/i
      show_map(user_id, thread_id, status)

    when /\[탐색종료\]/i
      end_exploration(user_id, thread_id, status)

    else
      nil
    end
  end

  private

  def get_thread_id(status)
    status[:in_reply_to_id] || status[:id]
  end

  def start_exploration(user_id, floor, thread_id, status)
    exploration_id = CoordinateExplorationSystem.start_exploration(
      [user_id],
      floor,
      thread_id,
      sheet_manager: @sheet_manager
    )

    return unless exploration_id

    exploration = CoordinateExplorationSystem.get(exploration_id)

    msg = "=" * 40 + "\n"
    msg += "#{exploration[:floor_name]} 탐색 시작\n"
    msg += "=" * 40 + "\n\n"
    msg += "개인 탐색 모드\n"
    msg += "조사 유형: #{exploration[:investigation_type]}\n\n"
    msg += "현재 위치: #{exploration[:position]} (#{CoordinateExplorationSystem::FLOOR_MAPS[floor][:grid][exploration[:position]][:name]})\n\n"
    msg += "명령어:\n"
    msg += "[이동/좌표] - 해당 좌표로 이동 (예: [이동/C4])\n"
    msg += "[조사/장소명] - 현재 위치 조사 (예: [조사/창고])\n"
    msg += "[맵보기] - 맵 확인\n"
    msg += "[탐색종료] - 탐색 종료"

    @mastodon_client.reply(status, msg)
  end

  def start_coop_exploration(initiator_id, floor, participants, thread_id, status)
    participants << initiator_id unless participants.include?(initiator_id)
    participants.uniq!

    exploration_id = CoordinateExplorationSystem.start_exploration(
      participants,
      floor,
      thread_id,
      sheet_manager: @sheet_manager
    )

    return unless exploration_id

    exploration = CoordinateExplorationSystem.get(exploration_id)

    msg = "=" * 40 + "\n"
    msg += "#{exploration[:floor_name]} 탐색 시작\n"
    msg += "=" * 40 + "\n\n"
    msg += "협력 탐색 모드 (#{participants.length}명)\n"
    msg += participants.map { |p| "@#{p}" }.join(', ') + "\n\n"
    msg += "조사 유형: #{exploration[:investigation_type]}\n\n"
    msg += "현재 위치: #{exploration[:position]} (#{CoordinateExplorationSystem::FLOOR_MAPS[floor][:grid][exploration[:position]][:name]})\n\n"
    msg += "명령어:\n"
    msg += "[이동/좌표] - 해당 좌표로 이동\n"
    msg += "[조사/장소명] - 현재 위치 조사\n"
    msg += "[맵보기] - 맵 확인\n"
    msg += "[탐색종료] - 탐색 종료"

    @mastodon_client.reply_with_mentions(status, msg, participants)
  end

  def move_to_coord(user_id, coord, thread_id, status)
    exploration = CoordinateExplorationSystem.find_by_thread(thread_id)

    unless exploration
      @mastodon_client.reply(status, "이 스레드에서 진행 중인 탐색이 없습니다.")
      return
    end

    result = CoordinateExplorationSystem.move_to(exploration[:exploration_id], user_id, coord)

    if result.is_a?(Hash) && result[:error]
      @mastodon_client.reply(status, result[:error])
      return
    end

    player = @sheet_manager.find_user(user_id)
    player_name = player ? (player["이름"] || user_id) : user_id

    msg = "@#{user_id}\n"
    msg += "#{result[:from]} → #{result[:to]}\n"
    msg += "#{player_name}이(가) #{result[:location][:name]}에 도착했습니다."

    if result[:location][:investigatable]
      msg += "\n\n[조사/#{result[:location][:name]}]으로 조사할 수 있습니다."
    end

    @mastodon_client.reply(status, msg)
  end

  def investigate_location_or_sub(user_id, location_or_sub, thread_id, status)
    exploration = CoordinateExplorationSystem.find_by_thread(thread_id)

    unless exploration
      @mastodon_client.reply(status, "이 스레드에서 진행 중인 탐색이 없습니다.")
      return
    end

    # 심층 조사 모드인 경우
    if CoordinateExplorationSystem.in_deep_investigation?(exploration[:exploration_id])
      investigate_sub_location(user_id, location_or_sub, thread_id, status)
    else
      # 일반 조사 모드
      investigate_location(user_id, location_or_sub, thread_id, status)
    end
  end

  def investigate_location(user_id, location, thread_id, status)
    exploration = CoordinateExplorationSystem.find_by_thread(thread_id)

    unless exploration
      @mastodon_client.reply(status, "이 스레드에서 진행 중인 탐색이 없습니다.")
      return
    end

    result = CoordinateExplorationSystem.investigate(exploration[:exploration_id], user_id, location)

    if result.is_a?(Hash) && result[:error]
      @mastodon_client.reply(status, result[:error])
      return
    end

    msg = "@#{user_id}\n"
    msg += "#{result[:location]}을(를) 조사합니다...\n\n"

    if result[:events].empty?
      msg += "아무것도 발견하지 못했습니다."
    else
      result[:events].each do |event|
        case event[:type]
        when 'clue'
          msg += build_clue_message(event[:data])
        when 'item'
          msg += build_item_message(event[:data], user_id)
        when 'encounter'
          msg += build_encounter_message(event[:data])
        end
      end
    end

    # 심층 조사 가능 여부 확인
    if CoordinateExplorationSystem.has_deep_investigation?(exploration[:exploration_id], result[:location])
      deep_info = CoordinateExplorationSystem.get_deep_investigation_info(exploration[:exploration_id], result[:location])
      
      msg += "\n" + "=" * 40 + "\n"
      msg += "더 자세히 조사할 수 있습니다\n"
      msg += "=" * 40 + "\n"
      msg += "#{deep_info[:description]}\n\n"
      msg += "[심층조사]로 세부 조사를 시작합니다\n"
      msg += "\n조사 가능 항목: " + deep_info[:sub_locations].join(', ')
    end

    @mastodon_client.reply(status, msg)
  end

  def show_map(user_id, thread_id, status)
    exploration = CoordinateExplorationSystem.find_by_thread(thread_id)

    unless exploration
      @mastodon_client.reply(status, "이 스레드에서 진행 중인 탐색이 없습니다.")
      return
    end

    map_text = CoordinateExplorationSystem.render_map(exploration[:exploration_id])

    msg = "@#{user_id}\n"
    msg += map_text

    @mastodon_client.reply(status, msg)
  end

  def start_deep_investigation_mode(user_id, thread_id, status)
    exploration = CoordinateExplorationSystem.find_by_thread(thread_id)

    unless exploration
      @mastodon_client.reply(status, "이 스레드에서 진행 중인 탐색이 없습니다.")
      return
    end

    unless exploration[:participants].include?(user_id)
      @mastodon_client.reply(status, "권한이 없습니다.")
      return
    end

    # 현재 위치의 장소 이름 가져오기
    map_info = CoordinateExplorationSystem::FLOOR_MAPS[exploration[:floor]]
    current_cell = map_info[:grid][exploration[:position]]
    location = current_cell[:name]

    # 심층 조사 가능 여부 확인
    unless CoordinateExplorationSystem.has_deep_investigation?(exploration[:exploration_id], location)
      @mastodon_client.reply(status, "이 장소는 심층 조사를 할 수 없습니다.")
      return
    end

    # 심층 조사 시작
    deep_inv = CoordinateExplorationSystem.start_deep_investigation(exploration[:exploration_id], location)

    msg = "=" * 40 + "\n"
    msg += "심층 조사 시작\n"
    msg += "=" * 40 + "\n\n"
    msg += "#{location} 내부를 자세히 조사합니다.\n\n"
    msg += "#{deep_inv[:description]}\n\n"
    msg += "조사 가능 항목:\n"
    deep_inv[:sub_locations].each do |item|
      msg += "- [조사/#{item}]\n"
    end
    msg += "\n[조사종료]로 탐색으로 돌아갑니다"

    @mastodon_client.reply(status, msg)
  end

  def investigate_sub_location(user_id, sub_location, thread_id, status)
    exploration = CoordinateExplorationSystem.find_by_thread(thread_id)

    unless exploration
      @mastodon_client.reply(status, "이 스레드에서 진행 중인 탐색이 없습니다.")
      return
    end

    unless exploration[:participants].include?(user_id)
      @mastodon_client.reply(status, "권한이 없습니다.")
      return
    end

    deep_inv = exploration[:deep_investigation]
    unless deep_inv
      @mastodon_client.reply(status, "심층 조사 모드가 아닙니다.")
      return
    end

    # 조사 가능 항목인지 확인
    unless deep_inv[:sub_locations].include?(sub_location)
      @mastodon_client.reply(status, "조사할 수 없는 항목입니다.\n\n조사 가능: #{deep_inv[:sub_locations].join(', ')}")
      return
    end

    # 조사 시트에서 조회 (위치 - 세부조사 형식)
    investigation_type = exploration[:investigation_type]
    main_location = deep_inv[:location]
    
    entry = @sheet_manager.find_investigation_entry_detailed(main_location, sub_location, investigation_type)

    unless entry
      @mastodon_client.reply(status, "#{sub_location}에 대한 조사 정보가 없습니다.")
      return
    end

    # 판정
    user = @sheet_manager.find_user(user_id)
    luck = (user["행운"] || 10).to_i
    dice = rand(1..20)
    difficulty = entry["난이도"].to_i
    total = dice + luck
    success = total >= difficulty

    result_text = success ? entry["성공결과"] : entry["실패결과"]

    # 조사 기록
    CoordinateExplorationSystem.record_deep_investigation(exploration[:exploration_id], sub_location)

    # 로그 기록
    @sheet_manager.log_investigation(
      user_id,
      "#{exploration[:floor_name]} - #{main_location}",
      sub_location,
      investigation_type,
      success,
      result_text
    )

    # 보상 처리
    if success && result_text
      # [아이템:이름] 처리
      if result_text =~ /\[아이템:([^\]]+)\]/
        item_name = $1
        @sheet_manager.add_item(user_id, item_name)
      end

      # [갈레온:숫자] 처리
      if result_text =~ /\[갈레온:(\d+)\]/
        amount = $1.to_i
        @sheet_manager.add_money(user_id, amount)
      end
    end

    msg = "@#{user_id}\n"
    msg += "=" * 40 + "\n"
    msg += "조사 결과\n"
    msg += "=" * 40 + "\n"
    msg += "대상: #{main_location} - #{sub_location}\n"
    msg += "판정: #{dice} + 행운 #{luck} = #{total}\n"
    msg += "난이도: #{difficulty}\n"
    msg += "결과: #{success ? '성공' : '실패'}\n\n"
    msg += result_text
    msg += "\n" + "=" * 40

    @mastodon_client.reply(status, msg)
  end

  def end_deep_investigation_mode(user_id, thread_id, status)
    exploration = CoordinateExplorationSystem.find_by_thread(thread_id)

    unless exploration
      @mastodon_client.reply(status, "이 스레드에서 진행 중인 탐색이 없습니다.")
      return
    end

    unless exploration[:participants].include?(user_id)
      @mastodon_client.reply(status, "권한이 없습니다.")
      return
    end

    result = CoordinateExplorationSystem.end_deep_investigation(exploration[:exploration_id])

    unless result
      @mastodon_client.reply(status, "심층 조사 모드가 아닙니다.")
      return
    end

    msg = "=" * 40 + "\n"
    msg += "심층 조사 종료\n"
    msg += "=" * 40 + "\n\n"
    msg += "#{result[:location]} 조사를 마쳤습니다.\n\n"
    msg += "조사한 항목: #{result[:investigated_count]}/#{result[:total_count]}\n\n"
    msg += "다시 탐색을 계속합니다.\n"
    msg += "현재 위치: #{exploration[:position]}\n\n"
    msg += "[이동/좌표]로 이동하거나\n"
    msg += "[탐색종료]로 탐색을 마칩니다"

    @mastodon_client.reply(status, msg)
  end

  def end_exploration(user_id, thread_id, status)
    exploration = CoordinateExplorationSystem.find_by_thread(thread_id)

    unless exploration
      @mastodon_client.reply(status, "이 스레드에서 진행 중인 탐색이 없습니다.")
      return
    end

    unless exploration[:participants].include?(user_id)
      @mastodon_client.reply(status, "권한이 없습니다.")
      return
    end

    summary = CoordinateExplorationSystem.end_exploration(exploration[:exploration_id])

    msg = "=" * 40 + "\n"
    msg += "탐색 종료\n"
    msg += "=" * 40 + "\n\n"
    msg += "장소: #{summary[:floor]}\n"
    msg += "발견한 단서: #{summary[:clues_found]}개\n"
    msg += "획득한 아이템: #{summary[:items_found]}개\n"
    msg += "처치한 적: #{summary[:enemies_defeated]}명\n\n"
    msg += "수고하셨습니다!"

    @mastodon_client.reply(status, msg)
  end

  def build_clue_message(clue)
    msg = "=" * 40 + "\n"
    msg += "단서 발견!\n"
    msg += "=" * 40 + "\n"
    msg += "대상: #{clue[:target]}\n"
    msg += "판정: #{clue[:dice]} + 행운 #{clue[:luck]} = #{clue[:total]}\n"
    msg += "난이도: #{clue[:difficulty]}\n"
    msg += "결과: #{clue[:success] ? '성공' : '실패'}\n\n"
    msg += clue[:result]
    msg += "\n" + "=" * 40 + "\n\n"
    msg
  end

  def build_item_message(item, user_id)
    msg = "=" * 40 + "\n"
    msg += "아이템 발견!\n"
    msg += "=" * 40 + "\n"
    msg += "#{item[:name]}\n"

    @sheet_manager.add_item(user_id, item[:name])

    msg += "인벤토리에 추가되었습니다.\n"
    msg += "=" * 40 + "\n\n"
    msg
  end

  def build_encounter_message(enemy)
    msg = "=" * 40 + "\n"
    msg += "적 조우!\n"
    msg += "=" * 40 + "\n"
    msg += "#{enemy[:full_name]}\n"
    msg += "HP: #{enemy[:hp]} / 공격: #{enemy[:atk]} / 방어: #{enemy[:def]}\n\n"
    msg += "[전투시작]으로 전투를 시작하세요!\n"
    msg += "=" * 40 + "\n\n"
    msg
  end
end
