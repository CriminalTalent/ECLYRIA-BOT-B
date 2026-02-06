# core/battle_state.rb
require 'securerandom'

class BattleState
  class << self
    attr_accessor :instance
  end

  def initialize
    @battles = {}
    @mutex = Mutex.new
  end

  def self.instance
    @instance ||= new
  end

  class << self
    def create(participants, type, thread_ts, channel, visibility = 'public')
      instance.create(participants, type, thread_ts, channel, visibility)
    end

    def get(battle_id)
      instance.get(battle_id)
    end

    def update(battle_id, state)
      instance.update(battle_id, state)
    end

    def clear(battle_id)
      instance.clear(battle_id)
    end

    def find_by_thread(thread_ts)
      instance.find_by_thread(thread_ts)
    end

    def find_by_participant(user_id)
      instance.find_by_participant(user_id)
    end

    def find_all_by_participant(user_id)
      instance.find_all_by_participant(user_id)
    end

    def find_by_thread_and_participant(thread_ts, user_id)
      instance.find_by_thread_and_participant(thread_ts, user_id)
    end
  end

  def create(participants, type, thread_ts, channel, visibility = 'public')
    @mutex.synchronize do
      battle_id = SecureRandom.uuid
      @battles[battle_id] = {
        battle_id: battle_id,
        participants: participants,
        type: type,
        thread_ts: thread_ts,
        channel: channel,
        visibility: visibility,
        current_turn: participants.first,
        round: 1,
        guarded: {},
        last_action_time: Time.now
      }
      puts "[BattleState] 전투 생성: #{battle_id} (#{participants.join(' vs ')})"
      battle_id
    end
  end

  def get(battle_id)
    @mutex.synchronize do
      @battles[battle_id]
    end
  end

  def update(battle_id, state)
    @mutex.synchronize do
      state[:last_action_time] = Time.now
      @battles[battle_id] = state
    end
  end

  def clear(battle_id)
    @mutex.synchronize do
      puts "[BattleState] 전투 종료: #{battle_id}"
      @battles.delete(battle_id)
    end
  end

  def find_by_thread(thread_ts)
    @mutex.synchronize do
      @battles.values.find { |b| b[:thread_ts] == thread_ts }
    end
  end

  def find_by_participant(user_id)
    @mutex.synchronize do
      battles = @battles.values.select { |b| b[:participants]&.include?(user_id) }
      battles.max_by { |b| b[:last_action_time] || Time.at(0) }
    end
  end

  def find_all_by_participant(user_id)
    @mutex.synchronize do
      @battles.values.select { |b| b[:participants]&.include?(user_id) }
    end
  end

  def find_by_thread_and_participant(thread_ts, user_id)
    @mutex.synchronize do
      @battles.values.find do |b|
        b[:thread_ts] == thread_ts && b[:participants]&.include?(user_id)
      end
    end
  end
end
