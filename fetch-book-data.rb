require 'yaml'
require 'net/http'
require 'json'
require 'open-uri'

outline = YAML.load_file('_data/outline.yml')

def fetch_book_info(title, subtitle, author)
  cover_image_path = image_path(title)
  if File.exist?(cover_image_path)
    puts "Already have a cover image for book '#{title}' at '#{cover_image_path}', will not download again"
    return
  end

  query = URI.encode_www_form_component("#{title} #{subtitle || author}")
  base_url = "https://openlibrary.org/search.json?q=#{query}&limit=1"
  response = Net::HTTP.get(URI(base_url))
  data = JSON.parse(response)

  if data['docs'] && !data['docs'].empty?
    book = data['docs'].first
    cover_id = book['cover_i']
    download_cover(title, cover_id, cover_image_path)
  else
    puts "WARN: Did not get any data for book with title '#{title}'"
  end
end

def dasherize(str)
  str.downcase.gsub(/[(),&:!]/, '').gsub(/[\s_]/, '-')
end

def image_path(title)
  "assets/img/books/#{dasherize(title)}.jpg"
end

def download_cover(title, cover_id, cover_image_path)
  unless cover_id
    puts "No cover image available for book '#{title}'"
    return
  end

  url = "https://covers.openlibrary.org/b/id/#{cover_id}-M.jpg"
  puts "Downloading cover image for book '#{title}' to '#{cover_image_path}'"
  download = open(url)
  IO.copy_stream(download, cover_image_path)
end

outline.each do |chapter|
  books = chapter['books']
  if books
    books.each do |book|
      fetch_book_info(book['title'], book['subtitle'], book['author'])
    end
  end
end
