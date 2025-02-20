require 'yaml'
require 'net/http'
require 'json'
require 'open-uri'

outline = YAML.load_file('_data/outline.yml')

def fetch_book_info(title, subtitle, author)
  query = URI.encode_www_form_component("#{title} #{subtitle}")
  base_url = "https://openlibrary.org/search.json?q=#{query}&limit=1"
  response = Net::HTTP.get(URI(base_url))
  data = JSON.parse(response)

  if data['docs'] && !data['docs'].empty?
    book = data['docs'].first
    cover_id = book['cover_i']
    download_cover(title, cover_id)
  else
    puts "WARN: Did not get any data for book with title '#{title}'"
  end
end

def dasherize(str)
  str.downcase.gsub(/[[:punct:]]/, '').gsub(/[\s_]/, '-')
end

def image_path(title)
  "assets/img/books/#{dasherize(title)}.jpg"
end

def download_cover(title, cover_id)
  unless cover_id
    puts "No cover image available for book '#{title}'"
    return
  end

  file_path = image_path(title)
  if File.exist?(file_path)
    puts "Cover image for book '#{title}' already exists at '#{file_path}', so won't download again."
    return
  end

  url = "https://covers.openlibrary.org/b/id/#{cover_id}-M.jpg"
  puts "Downloading cover image for book '#{title}' to '#{file_path}'"
  download = open(url)
  IO.copy_stream(download, file_path)
end

count = 0

outline.each do |chapter|
  books = chapter['books']
  if books
    books.each do |book|
      count += 1
      fetch_book_info(book['title'], book['subtitle'], book['author'])

      if count >= 10
        raise "Exiting at max count"
      end
    end
  end
end
