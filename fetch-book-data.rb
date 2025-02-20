require 'yaml'
require 'json'
require 'open-uri'
require 'nokogiri'

def fetch_description_from_open_library(title, subtitle, author)
  query = URI.encode_www_form_component("#{title} #{subtitle || author}")
  base_url = "https://openlibrary.org/search.json?q=#{query}&limit=1"
  response = make_http_request_with_retries(base_url)
  data = JSON.parse(response.string)

  if data['docs'] && !data['docs'].empty?
    book = data['docs'].first
    olid = book['key']

    description_url = "https://openlibrary.org#{olid}.json"
    description_response = make_http_request_with_retries(description_url)

    extract_description(description_response.string, book)
  else
    puts "WARN: Did not get any data for book with title '#{title}'"
  end
end

def make_http_request_with_retries(url)
  max_retries = 3
  sec_between_retries = 3
  retries = 0

  begin
    URI.open(url)
  rescue => error
    puts "WARN: Got error while calling URL '#{url}': '#{error}'"
    retries += 1
    if retries < max_retries
      puts "This was attempt #{retries}. Will sleep for #{sec_between_retries} and try again"
      sleep(sec_between_retries)
      retry
    else
      raise "Failed to call URL '#{url}' after #{retries} retries."
    end
  end
end

def fetch_description_from_goodreads(title, subtitle, author)
  query = URI.encode_www_form_component("#{title} #{subtitle || author}")
  search_url = "https://www.goodreads.com/search?q=#{query}"
  doc = Nokogiri::HTML(make_http_request_with_retries(search_url))

  first_result = doc.at_css("a.bookTitle")
  return nil unless first_result

  book_url = "https://www.goodreads.com" + first_result["href"]
  book_page = Nokogiri::HTML(make_http_request_with_retries(book_url))

  book_page.at_css("div.DetailsLayoutRightParagraph__widthConstrained")&.text&.strip
end

def extract_description(description_response, book)
  description_data = JSON.parse(description_response)

  description = description_data['description']
  description = description['value'] if description &&
  if description
    if description.is_a?(Hash)
      return description['value']
    else
      return description
    end
  end

  excerpts = description_data['excerpts']
  if excerpts
    return excerpts.first['excerpt']
  end

  first_sentence = book['first_sentence']
  if first_sentence
    return first_sentence.first
  end

  nil
end

def fetch_book_cover_image_from_open_library(title, subtitle, author)
  cover_image_path = image_path(title)
  if File.exist?(cover_image_path)
    puts "Already have a cover image for book '#{title}' at '#{cover_image_path}', will not download again"
    return cover_image_path
  end

  query = URI.encode_www_form_component("#{title} #{subtitle || author}")
  base_url = "https://openlibrary.org/search.json?q=#{query}&limit=1"
  response = make_http_request_with_retries(base_url)
  data = JSON.parse(response.string)

  if data['docs'] && !data['docs'].empty?
    book = data['docs'].first
    cover_id = book['cover_i']
    download_cover(title, cover_id, cover_image_path)
  else
    puts "WARN: Did not get any data for book with title '#{title}'"
    nil
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
    return nil
  end

  url = "https://covers.openlibrary.org/b/id/#{cover_id}-M.jpg"
  puts "Downloading cover image for book '#{title}' to '#{cover_image_path}'"
  download = open(url)
  IO.copy_stream(download, cover_image_path)

  cover_image_path
end

# Ruby has no way to update YAML without completely changing the formatting, so to avoid turning outline.yaml into a
# hot mess, this is a hacky method that uses regex to insert YAML elements into the book field of the YAML.
def add_element_to_book_yaml(title, outline_as_str, element_name, element_value)
  unless element_value
    puts "WARN: did not find a '#{element_name}' for '#{title}'"
    return outline_as_str
  end

  puts "Adding '#{element_name}' to YAML for '#{title}'"
  element_value = element_value.gsub('"', "'").gsub("\n", " ")
  outline_as_str.gsub(/^(    - title: "#{title}")/, "\\1\n      #{element_name}: \"#{element_value}\"")
end

def process_outline(outline, outline_as_str, max_to_process)
  count = 0
  outline.each do |chapter|
    books = chapter['books']
    if books
      books.each do |book|
        count += 1

        title = book['title']
        subtitle = book['subtitle']
        author = book['author']
        image = book['image']
        description = book['description']

        if description
          puts "Book '#{title}' already has a description. Will not try to update it."
        else
          description = fetch_description_from_open_library(title, subtitle, author) || fetch_description_from_goodreads(title, subtitle, author)
          outline_as_str = add_element_to_book_yaml(title, outline_as_str, 'description', description)
        end

        if image
          puts "Book '#{title}' already has an image. Will not try to update it."
        else
          image_file_path = fetch_book_cover_image_from_open_library(title, author, description)
          outline_as_str = add_element_to_book_yaml(title, outline_as_str, 'image', image_file_path)
        end

        if max_to_process && count >= max_to_process
          puts "Hit max count of #{max_to_process}, so will not process the outline further."
          return outline_as_str
        end
      end
    end
  end

  outline_as_str
end

outline_file_path = '_data/outline.yml'
outline = YAML.load_file(outline_file_path)
outline_as_str = File.read(outline_file_path)

# Set to nil to process all books
max_to_process = nil

updated_outline_as_str = process_outline(outline, outline_as_str, max_to_process)
puts "Updating '#{outline_file_path}'"
File.write(outline_file_path, updated_outline_as_str)