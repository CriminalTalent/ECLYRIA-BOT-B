#!/usr/bin/env ruby
require 'dotenv'
Dotenv.load

require_relative 'mastodon_client'
require_relative 'sheet_manager'
require_relative 'command_parser'

BASE_URL = ENV['MASTODON_BASE_URL']
TOKEN = ENV['MASTODON_TOKEN']
SHEET_ID = ENV['GOOGLE_SHEET_ID']
CREDENTIALS_PATH = ENV['GOOGLE_CREDENTIALS_PATH']

puts "Starting Battle Bot..."
puts "Base URL: #{BASE_URL}"

mastodon = MastodonClient.new(BASE_URL, TOKEN)
sheet_manager = SheetManager.new(SHEET_ID, CREDENTIALS_PATH)
parser = CommandParser.new(mastodon, sheet_manager)

last_id = nil
puts "Listening for notifications..."

loop do
  begin
    notifications = mastodon.notifications(since_id: last_id, limit: 40)
    
    if notifications.any?
      last_id = notifications.first['id']
      
      notifications.reverse.each do |notification|
        next unless notification['type'] == 'mention'
        
        status = notification['status']
        next unless status
        
        content = status['content']
        clean_text = content.gsub(/<\/?[^>]*>/, "").strip
        
        account = status['account']
        user_id = "@#{account['username']}@#{BASE_URL.split('//').last}"
        
        puts "\n[#{Time.now}] @#{account['username']}: #{clean_text}"
        
        parser.parse(clean_text, user_id, status['id'])
      end
    end
    
    sleep 3
    
  rescue => e
    puts "Error: #{e.message}"
    puts e.backtrace.join("\n")
    sleep 10
  end
end
