# mastodon_client.rb

require 'mastodon'
require 'dotenv/load'

class MastodonClient
  def initialize
    @client = Mastodon::REST::Client.new(
      base_url: ENV['MASTODON_BASE_URL'],
      bearer_token: ENV['MASTODON_ACCESS_TOKEN']
    )
    @account = @client.verify_credentials
  end

  def reply(to_user, text, in_reply_to_id: nil)
    status = "@#{to_user} #{text}"
    @client.create_status(status, in_reply_to_id: in_reply_to_id)
  end

  def say(text)
    @client.create_status(text)
  end

  def boost(status_id)
    @client.reblog(status_id)
  end

  def account_id
    @account.acct
  end
end

