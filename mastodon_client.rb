# mastodon_client.rb

require 'mastodon'
require 'dotenv/load'

class MastodonClient
  def initialize
    @client = Mastodon::REST::Client.new(
      base_url: ENV['MASTODON_BASE_URL'],
      bearer_token: ENV['MASTODON_ACCESS_TOKEN']
    )
    @me = @client.verify_credentials
  end

  def say(text)
    @client.create_status(text)
  end

  def reply(user_id, text, in_reply_to_id: nil)
    @client.create_status("@#{user_id} #{text}", in_reply_to_id: in_reply_to_id)
  end

  def me
    @me.
