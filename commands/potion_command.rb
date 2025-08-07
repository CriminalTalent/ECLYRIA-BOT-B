# commands/potion_command.rb

require_relative '../core/sheet_manager'

class PotionCommand
  def initialize(masto_client, sheet)
    @client = masto_client
    @sheet = sheet
  end

  def handle(status)
    content = status[:content]
    user_id = status[:account][:acct]

    return unless content.include?("물약사용")

    items = SheetManager.get_stat(user_id, "아이템")
    hp = SheetManager.get_stat(user_id, "체력")

    potions = extract_potion_count(items)
    if potions == 0
      @client.reply("@#{user_id} 포션이 없습니다.")
      return
    end

    heal = [5, 10, 15, 20].sample
    new_hp = hp + heal

    # 체력 업데이트
    SheetManager.set_stat(user_id, "체력", new_hp)

    # 포션 1개 차감
    new_items = decrement_potion(items)
    SheetManager.set_stat(user_id, "아이템", new_items)

    @client.create_status("@#{user_id}의 체력이 #{heal} 회복되었습니다. 현재 체력 #{new_hp}")
  end

  private

  def extract_potion_count(items)
    return 0 unless items

    items.split(',').map(&:strip).each do |entry|
      name, count = entry.split(':')
      return count.to_i if name == "포션"
    end

    0
  end

  def decrement_potion(items)
    return items unless items

    new_items = items.split(',').map(&:strip).map do |entry|
      name, count = entry.split(':')
      if name == "포션"
        new_count = count.to_i - 1
        new_count > 0 ? "포션:#{new_count}" : nil
      else
        entry
      end
    end.compact

    new_items.join(', ')
  end
end

