require 'json'

class MapCache
  FILE_PATH = "map_data.json"

  def self.load
    JSON.parse(File.read(FILE_PATH))
  end

  def self.save(data)
    File.write(FILE_PATH, JSON.pretty_generate(data))
  end
end
