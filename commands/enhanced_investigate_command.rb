# commands/enhanced_investigate_command.rb
require 'date'

class EnhancedInvestigateCommand
  def initialize(mastodon_client, sheet_manager)
    @mastodon_client = mastodon_client
    @sheet_manager = sheet_manager
  end

  def handle(status)
    content = status.content.gsub(/<[^>]+>/, '').strip
    sender_full = status.account.acct
    sender = sender_full.split('@').first
    in_reply_to_id = status.id

    case content
    when /\[조사\/(.+?)\]/
      target = $1
      handle_basic_investigation(sender, target, status)
    when /\[정밀조사\/(.+?)\]/
      target = $1
      handle_detailed_investigation(sender, target, status)
    when /\[훔쳐보기\/(.+?)\]/
      target = $1
      handle_stealth_investigation(sender, target, status)
    when /\[이동\/(.+?)\]/
      location = $1
      handle_move(sender, location, status)
    when /\[위치확인\]/
      handle_location_check(sender, status)
    when /\[주변탐색\]/
      handle_area_search(sender, status)
    when /\[은신\]/
      handle_stealth(sender, status)
    when /\[협력조사\/(.+?)\/@?(\w+)\]/
      target = $1
      partner = $2
      handle_cooperative_investigation(sender, target, partner, status)
    when /\[방해\/@?(\w+)\]/
      target_investigator = $1
      handle_interference(sender, target_investigator, status)
    when /\[물건이동\/(.+?)\/(.+?)\]/
      item = $1
      new_location = $2
      handle_item_move(sender, item, new_location, status)
    when /\[숨기기\/(.+?)\/(.+?)\]/
      item = $1
      hiding_place = $2
      handle_hide_item(sender, item, hiding_place, status)
    when /\[흔적조사\/(.+?)\]/
      location = $1
      handle_trace_investigation(sender, location, status)
    when /\[공격\/@?(\w+)\]/
      target = $1
      handle_targeted_attack(sender, target, status)
    when /\[방어\/@?(\w+)\]/
      target = $1
      handle_targeted_defense(sender, target, status)
    else
      @mastodon_client.reply(status, "인식되지 않은 명령어입니다.")
    end
  end

  private

  def handle_basic_investigation(user, target, status)
    investigation = @sheet_manager.find_investigation(target, "조사")
    
    if investigation && investigation["결과"]
      result = investigation["결과"]
      @mastodon_client.reply(status, "#{target}에 대한 조사 결과:\n#{result}")
    else
      @mastodon_client.reply(status, "#{target}에 대한 조사 정보를 찾을 수 없습니다.")
    end
  end

  def handle_detailed_investigation(user, target, status)
    investigation = @sheet_manager.find_investigation(target, "정밀조사")
    
    if investigation && investigation["결과"]
      result = investigation["결과"]
      @mastodon_client.reply(status, "#{target}에 대한 정밀조사 결과:\n#{result}")
    else
      @mastodon_client.reply(status, "#{target}에 대한 정밀조사 정보를 찾을 수 없습니다.")
    end
  end

  def handle_stealth_investigation(user, target, status)
    investigation = @sheet_manager.find_investigation(target, "훔쳐보기")
    
    if investigation && investigation["결과"]
      result = investigation["결과"]
      # 훔쳐보기는 DM으로 전송
      @mastodon_client.dm(user, "#{target}에 대한 은밀 조사 결과:\n#{result}")
      @mastodon_client.reply(status, "조사를 진행했습니다. 결과는 DM으로 전송되었습니다.")
    else
      @mastodon_client.reply(status, "#{target}에 대한 조사 정보를 찾을 수 없습니다.")
    end
  end

  def handle_move(user, location, status)
    @mastodon_client.reply(status, "#{user}이(가) #{location}(으)로 이동했습니다.")
  end

  def handle_location_check(user, status)
    @mastodon_client.reply(status, "현재 위치 확인 기능은 DM이 수동으로 관리합니다.")
  end

  def handle_area_search(user, status)
    @mastodon_client.reply(status, "주변을 탐색했습니다. 특별한 것은 발견되지 않았습니다.")
  end

  def handle_stealth(user, status)
    @mastodon_client.reply(status, "#{user}이(가) 은신했습니다.")
  end

  def handle_cooperative_investigation(user, target, partner, status)
    @mastodon_client.reply(status, "#{user}와 #{partner}가 협력하여 #{target}을(를) 조사합니다.")
  end

  def handle_interference(user, target_investigator, status)
    @mastodon_client.reply(status, "#{user}이(가) #{target_investigator}의 조사를 방해했습니다.")
  end

  def handle_item_move(user, item, new_location, status)
    @mastodon_client.reply(status, "#{user}이(가) #{item}을(를) #{new_location}(으)로 이동시켰습니다.")
  end

  def handle_hide_item(user, item, hiding_place, status)
    @mastodon_client.reply(status, "#{user}이(가) #{item}을(를) #{hiding_place}에 숨겼습니다.")
  end

  def handle_trace_investigation(user, location, status)
    @mastodon_client.reply(status, "#{location}의 흔적을 조사했습니다.")
  end

  def handle_targeted_attack(user, target, status)
    # 전투 중인지 확인
    unless defined?(BattleState) && BattleState.in_battle?(user)
      @mastodon_client.reply(status, "전투 중이 아닙니다.")
      return
    end

    # 턴 확인
    unless BattleState.is_current_turn?(user)
      @mastodon_client.reply(status, "당신의 턴이 아닙니다.")
      return
    end

    # 대상이 전투에 참여 중인지 확인
    unless BattleState.in_battle?(target)
      @mastodon_client.reply(status, "#{target}는 이 전투에 참여하지 않았습니다.")
      return
    end

    # 자기 자신을 공격할 수 없음
    if user == target
      @mastodon_client.reply(status, "자기 자신을 공격할 수 없습니다.")
      return
    end

    # 일반 공격 수행
    BattleEngine.attack(user) if defined?(BattleEngine)
  end
  
  def handle_targeted_defense(user, target, status)
    # 전투 중인지 확인
    unless defined?(BattleState) && BattleState.in_battle?(user)
      @mastodon_client.reply(status, "전투 중이 아닙니다.")
      return
    end

    # 턴 확인
    unless BattleState.is_current_turn?(user)
      @mastodon_client.reply(status, "당신의 턴이 아닙니다.")
      return
    end

    # 방어 수행
    msg = "#{user}이(가) #{target}를 보호하는 방어 자세를 취합니다."
    BattleState.say(msg) if defined?(BattleState)
    BattleState.next_turn if defined?(BattleState)
  end

  def get_location_info(location)
    values = @sheet_manager.read_values("장소정보!A:C")
    if values && values.length > 1
      values.each_with_index do |row, index|
        next if index == 0
        if row[0] == location
          return {
            description: row[1] || "특별한 설명이 없는 장소입니다.",
            actions: row[2] || "[조사] [정밀조사] [훔쳐보기]"
          }
        end
      end
    end
    
    {
      description: "#{location}는 조용하고 평범한 장소입니다.",
      actions: "[조사] [정밀조사] [훔쳐보기]"
    }
  end

  def get_encounter_event(location)
    values = @sheet_manager.read_values("마주침이벤트!A:E")
    return nil if values.nil? || values.empty?
    
    values.each_with_index do |row, index|
      next if index == 0
      if row[0] == location
        return {
          character: row[1],
          description: row[2]
        }
      end
    end
    nil
  end
end
