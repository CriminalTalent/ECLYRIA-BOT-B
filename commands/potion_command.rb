# commands/potion_command.rb

class PotionCommand
  def initialize(mastodon_client, sheet_manager)
    @mastodon_client = mastodon_client
    @sheet_manager = sheet_manager
  end

  def handle(status)
    sender_full = status.account.acct
    sender = sender_full.split('@').first
    in_reply_to_id = status.id
    
    inventory = @sheet_manager.get_stat(sender, "아이템")
    return unless inventory

    potion_line = inventory.split(',').find { |i| i.include?("물약") }
    unless potion_line
      @mastodon_client.reply(sender, "물약을 가지고 있지 않습니다.", in_reply_to_id: in_reply_to_id)
      return
    end

    count = potion_line.match(/물약:?(\d+)/)&.[](1)&.to_i || 0
    if count <= 0
      @mastodon_client.reply(sender, "물약이 없습니다.", in_reply_to_id: in_reply_to_id)
      return
    end

    # 랜덤 회복량
    amount = [5, 10, 15, 20].sample
    hp_str = @sheet_manager.get_stat(sender, "체력")
    hp = hp_str ? hp_str.to_i : 100
    new_hp = [hp + amount, 100].min

    @sheet_manager.set_stat(sender, "체력", new_hp)

    # 포션 차감
    new_inventory = inventory.gsub(/물약:?\d*/) { "물약:#{count - 1}" }
    @sheet_manager.set_stat(sender, "아이템", new_inventory)

    message = "#{sender}의 체력이 #{amount} 회복되었습니다. 현재 체력 #{new_hp}"
    @mastodon_client.say(message)
  end
end
