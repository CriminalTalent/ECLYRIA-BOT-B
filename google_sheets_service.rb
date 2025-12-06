require 'google/apis/sheets_v4'
require 'googleauth'

class GoogleSheetsService
  SPREADSHEET_ID = ENV['GOOGLE_SHEET_ID']

  RANGE_LOCATIONS = "위치!A2:F"
  RANGE_EXPLORE = "조사!A2:F"

  def initialize
    @service = Google::Apis::SheetsV4::SheetsService.new
    @service.client_options.application_name = "Clarisse Map Server"
    @service.authorization = Google::Auth::ServiceAccountCredentials.make_creds(
      json_key_io: File.open(ENV['GOOGLE_APPLICATION_CREDENTIALS']),
      scope: Google::Apis::SheetsV4::AUTH_SPREADSHEETS_READONLY
    )
    @service.authorization.fetch_access_token!
  end

  def load_locations
    data = @service.get_spreadsheet_values(SPREADSHEET_ID, RANGE_LOCATIONS).values || []
    data.map do |row|
      {
        id: row[0],
        location: row[2]
      }
    end
  end

  def load_explore_details
    data = @service.get_spreadsheet_values(SPREADSHEET_ID, RANGE_EXPLORE).values || []
    data.map do |row|
      {
        name: row[0],
        sub: row[1],
        desc: row[2],
        type: row[3],
        difficulty: row[4],
        success: row[5] || "",
        failure: row[6] || ""
      }
    end
  end
end
