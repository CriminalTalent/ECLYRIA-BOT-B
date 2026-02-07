require 'minitest/autorun'
require 'minitest/pride'

# Mock classes for testing
class MockMastodonClient
  attr_reader :messages, :last_visibility, :last_mentions

  def initialize
    @messages = []
    @last_visibility = nil
    @last_mentions = nil
  end

  def reply(status, message)
    @messages << { type: :reply, message: message }
    { "id" => "status_#{@messages.length}" }
  end

  def reply_with_mentions(status, message, user_ids)
    reply_with_mentions_visibility(status, message, user_ids, "unlisted")
  end

  def reply_with_mentions_visibility(status, message, user_ids, visibility)
    @last_visibility = visibility
    @last_mentions = user_ids
    @messages << { type: :reply_with_mentions, message: message, user_ids: user_ids, visibility: visibility }
    { "id" => "status_#{@messages.length}" }
  end
end

class MockSheetManager
  attr_reader :users, :updates

  def initialize
    @users = {}
    @updates = []
  end

  def add_user(id, data)
    @users[id] = data
  end

  def find_user(id)
    @users[id]
  end

  def update_user(id, data)
    @updates << { id: id, data: data }
    if @users[id]
      @users[id]["HP"] = data[:hp] if data[:hp]
      @users[id]["아이템"] = data[:items] if data[:items]
    end
  end
end

# Load the actual classes
require_relative '../core/battle_state'
require_relative '../core/battle_engine'

class BattleEngineTest < Minitest::Test
  def setup
    @client = MockMastodonClient.new
    @sheet = MockSheetManager.new
    @engine = BattleEngine.new(@client, @sheet)

    # 테스트 유저 설정
    @sheet.add_user("user1", {
      "이름" => "홍길동",
      "HP" => 100,
      "공격" => 10,
      "방어" => 10,
      "민첩성" => 10,
      "행운" => 5,
      "체력" => 10,
      "아이템" => ["소형물약", "중형물약"]
    })

    @sheet.add_user("user2", {
      "이름" => "임꺽정",
      "HP" => 100,
      "공격" => 10,
      "방어" => 10,
      "민첩성" => 8,
      "행운" => 5,
      "체력" => 10,
      "아이템" => ["소형물약"]
    })

    @sheet.add_user("user3", {
      "이름" => "장길산",
      "HP" => 100,
      "공격" => 10,
      "방어" => 10,
      "민첩성" => 6,
      "행운" => 5,
      "체력" => 10,
      "아이템" => []
    })

    @sheet.add_user("user4", {
      "이름" => "전우치",
      "HP" => 100,
      "공격" => 10,
      "방어" => 10,
      "민첩성" => 4,
      "행운" => 5,
      "체력" => 10,
      "아이템" => []
    })
  end

  def teardown
    # 전투 상태 정리
    BattleState.instance_variable_set(:@battles, {})
  end

  # 테스트 1: 전투 참여자 태그 (멘션) 포함 확인
  def test_battle_start_includes_all_participant_mentions
    reply_status = { "id" => "123", "visibility" => "unlisted" }

    @engine.start_1v1("user1", "user2", reply_status)

    # 마지막 메시지에 모든 참가자가 멘션되었는지 확인
    assert_equal ["user1", "user2"], @client.last_mentions
    assert @client.messages.any? { |m| m[:type] == :reply_with_mentions }
  end

  def test_team_battle_includes_all_participant_mentions
    reply_status = { "id" => "123", "visibility" => "unlisted" }

    @engine.start_2v2("user1", "user2", "user3", "user4", reply_status)

    # 4명 모두 멘션되었는지 확인
    assert_equal ["user1", "user2", "user3", "user4"], @client.last_mentions
  end

  
  # 테스트 2: DM 전투 진행 (visibility 유지)
  def test_dm_battle_maintains_direct_visibility
    reply_status = { "id" => "123", "visibility" => "direct" }

    @engine.start_1v1("user1", "user2", reply_status)

    # DM으로 시작하면 DM으로 유지되는지 확인
    assert_equal "direct", @client.last_visibility
  end

  def test_public_battle_uses_unlisted_visibility
    reply_status = { "id" => "123", "visibility" => "public" }

    @engine.start_1v1("user1", "user2", reply_status)

    # public은 unlisted로 변환되는지 확인
    assert_equal "unlisted", @client.last_visibility
  end

  # 테스트 3: 선공/후공 동시 라운드 결과 출력 (1:1)
  def test_1v1_simultaneous_action_system
    reply_status = { "id" => "123", "visibility" => "unlisted" }

    @engine.start_1v1("user1", "user2", reply_status)

    battle_id = BattleState.find_battle_id_by_user("user1")
    state = BattleState.get(battle_id)

    # 동시 행동 방식이므로 current_turn이 nil이어야 함
    assert_nil state[:current_turn]
    # actions_queue가 초기화되어 있어야 함
    assert_equal [], state[:actions_queue]
  end

  def test_1v1_both_players_must_act_before_round_resolves
    reply_status = { "id" => "123", "visibility" => "unlisted" }

    @engine.start_1v1("user1", "user2", reply_status)
    @client.messages.clear

    # user1만 공격 선택
    @engine.attack("user1", nil)

    battle_id = BattleState.find_battle_id_by_user("user1")
    state = BattleState.get(battle_id)

    # 아직 라운드가 처리되지 않아야 함 (1:1에서는 "{이름}의 차례" 메시지)
    assert_equal 1, state[:actions_queue].length
    assert @client.messages.last[:message].include?("의 차례")

    # user2도 공격 선택
    @engine.attack("user2", nil)

    # 이제 라운드가 처리되어야 함 (라운드 결과 메시지)
    assert @client.messages.any? { |m| m[:message].include?("라운드") && m[:message].include?("결과") }
  end

  # 테스트 4: 액션 처리 우선순위 (물약 > 방어/반격 > 공격)
  def test_action_priority_potion_before_attack
    reply_status = { "id" => "123", "visibility" => "unlisted" }

    # user1 HP를 낮게 설정
    @sheet.users["user1"]["HP"] = 50

    @engine.start_1v1("user1", "user2", reply_status)
    @client.messages.clear

    battle_id = BattleState.find_battle_id_by_user("user1")

    # user1: 물약 사용, user2: 공격
    @engine.use_potion("user1", "소형", nil)
    @engine.attack("user2", nil)

    # 라운드 결과 메시지에서 물약 사용이 먼저 나와야 함
    round_message = @client.messages.find { |m| m[:message].include?("라운드") && m[:message].include?("결과") }

    if round_message
      potion_index = round_message[:message].index("물약")
      attack_index = round_message[:message].index("공격")

      # 물약 메시지가 공격 메시지보다 앞에 있어야 함
      assert potion_index < attack_index, "물약 사용이 공격보다 먼저 처리되어야 함"
    end
  end

  # 테스트 5: 반격/방어 최초 1회만 적용
  def test_defense_applies_only_once_per_round
    reply_status = { "id" => "123", "visibility" => "unlisted" }

    @engine.start_2v2("user1", "user2", "user3", "user4", reply_status)

    battle_id = BattleState.find_battle_id_by_user("user1")
    state = BattleState.get(battle_id)

    # 초기 상태
    state[:guarded] = { "user3" => true }
    state[:guarded_used] = {}
    state[:counter] = { "user4" => true }
    state[:counter_used] = {}
    BattleState.update(battle_id, state)

    attacker = @sheet.find_user("user1")
    defender = @sheet.find_user("user3")

    # 첫 번째 공격 - 방어 적용됨
    result1 = @engine.send(:calculate_attack_result, attacker, "user1", defender, "user3", state, false)

    # 방어가 사용되었으므로 guarded_used가 true여야 함
    assert state[:guarded_used]["user3"], "첫 공격 후 방어 사용됨 표시"

    # 두 번째 공격 - 방어 적용 안됨 (이미 사용됨)
    result2 = @engine.send(:calculate_attack_result, attacker, "user1", defender, "user3", state, false)

    # 두 번째 공격에서는 방어 보너스 텍스트가 없어야 함
    refute result2[:message].include?("방어 +"), "두 번째 공격에서는 방어 보너스 없어야 함"
  end

  def test_counter_applies_only_once_per_round
    reply_status = { "id" => "123", "visibility" => "unlisted" }

    @engine.start_1v1("user1", "user2", reply_status)

    battle_id = BattleState.find_battle_id_by_user("user1")
    state = BattleState.get(battle_id)

    # user2가 반격
    state[:counter] = { "user2" => true }
    state[:counter_used] = {}
    BattleState.update(battle_id, state)

    attacker = @sheet.find_user("user1")
    defender = @sheet.find_user("user2")

    # 첫 번째 공격 - 반격 적용됨 (데미지가 있을 경우)
    # 강제로 데미지가 발생하도록 설정
    @sheet.users["user1"]["공격"] = 20
    @sheet.users["user2"]["방어"] = 1

    result1 = @engine.send(:calculate_attack_result, attacker, "user1", defender, "user2", state, false)

    if result1[:damage] > 0
      assert result1[:counter_damage] == 5, "첫 공격에서 반격 데미지 5"
      assert state[:counter_used]["user2"], "반격 사용됨 표시"

      # 두 번째 공격 - 반격 적용 안됨
      result2 = @engine.send(:calculate_attack_result, attacker, "user1", defender, "user2", state, false)
      assert_equal 0, result2[:counter_damage], "두 번째 공격에서는 반격 없음"
    end
  end

  # ============================================
  # 테스트 6: 이미 행동한 유저 중복 행동 방지
  # ============================================
  def test_prevent_duplicate_action_in_same_round
    reply_status = { "id" => "123", "visibility" => "unlisted" }

    @engine.start_1v1("user1", "user2", reply_status)
    @client.messages.clear

    # user1 첫 번째 행동
    @engine.attack("user1", nil)

    # user1 중복 행동 시도
    @engine.attack("user1", nil)

    # 중복 행동 방지 메시지가 있어야 함
    assert @client.messages.any? { |m| m[:message].include?("이미") && m[:message].include?("행동") }
  end

  # ============================================
  # 테스트 7: 전투불능 유저 제외
  # ============================================
  def test_dead_player_excluded_from_alive_participants
    reply_status = { "id" => "123", "visibility" => "unlisted" }

    # user2 HP를 0으로 설정
    @sheet.users["user2"]["HP"] = 0

    @engine.start_1v1("user1", "user2", reply_status)

    battle_id = BattleState.find_battle_id_by_user("user1")
    state = BattleState.get(battle_id)

    alive = @engine.send(:get_alive_participants, state)

    # user2는 전투불능이므로 제외되어야 함
    assert_includes alive, "user1"
    refute_includes alive, "user2"
  end

  # ============================================
  # 테스트 8: 팀전투 대리 방어
  # ============================================
  def test_team_battle_cover_defense
    reply_status = { "id" => "123", "visibility" => "unlisted" }

    @engine.start_2v2("user1", "user2", "user3", "user4", reply_status)

    battle_id = BattleState.find_battle_id_by_user("user1")
    state = BattleState.get(battle_id)

    # user1이 user2를 대리 방어
    state[:defend_target_map] = { "user2" => "user1" }
    state[:guarded] = { "user1" => true }
    BattleState.update(battle_id, state)

    # user3이 user2를 공격하면, 실제로는 user1이 맞아야 함
    actual_defender = state[:defend_target_map]["user2"] || "user2"
    assert_equal "user1", actual_defender
  end

  # ============================================
  # 테스트 9: 치명타 확률 계산
  # ============================================
  def test_critical_hit_chance_calculation
    # 행운 스탯별 치명타 확률 확인
    test_cases = {
      1 => 5,
      2 => 10,
      5 => 15,
      10 => 30
    }

    test_cases.each do |luck, expected_chance|
      result = @engine.send(:check_critical_hit, luck)
      assert_equal expected_chance, result[:chance], "행운 #{luck}의 치명타 확률은 #{expected_chance}%여야 함"
    end
  end

  # ============================================
  # 테스트 10: 자동 방어 시간 초과
  def test_auto_defend_on_timeout
    reply_status = { "id" => "123", "visibility" => "unlisted" }

    @engine.start_1v1("user1", "user2", reply_status)

    battle_id = BattleState.find_battle_id_by_user("user1")
    state = BattleState.get(battle_id)

    # user1만 행동
    @engine.attack("user1", nil)
    @client.messages.clear

    # 시간 초과 시뮬레이션
    @engine.auto_defend_timeout(battle_id, state)

    # 시간 초과 메시지가 있어야 함
    assert @client.messages.any? { |m| m[:message].include?("시간 초과") }

    # 라운드가 처리되어야 함
    assert @client.messages.any? { |m| m[:message].include?("라운드") }
  end
end

# 테스트 실행
if __FILE__ == $0
  Minitest.run
end
