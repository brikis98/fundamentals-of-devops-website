require 'yaml'
require 'json'
require 'open-uri'
require 'nokogiri'
require 'mini_magick'
require 'fileutils'
require 'selenium-webdriver'

def fetch_book_description_from_open_library(title, subtitle, author)
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

$max_retries = 3
$sec_between_retries = 3

def make_http_request_with_retries(url)
  retries = 0

  begin
    URI.open(url,
             :read_timeout => 5,
             "user-agent" => "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36",
             "accept" => "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7'",
             "accept-language" => "en-US,en;q=0.9"
    )
  rescue => error
    # https://stackoverflow.com/a/39160567
    # URI.open doesn't allow redirecting https to http... So this is a massive hack to allow it manually by
    # updating the URL to the http one and trying again.
    # The error message will be:
    #
    # redirection forbidden: HTTPS_URL -> HTTP_URL
    if match = error.message.match(/redirection forbidden: http.+ -> (.+)/)
      url = match.captures[0]
      puts "WARN: Got redirection error, updating URI to '#{url}'"
    end
    puts "WARN: Got error while calling URL '#{url}': '#{error}'"
    retries += 1
    if retries < $max_retries
      puts "This was attempt #{retries}. Will sleep for #{$sec_between_retries} and try again"
      sleep($sec_between_retries)
      retry
    else
      raise "Failed to call URL '#{url}' after #{retries} retries. Most recent error: '#{error}'"
    end
  end
end

def fetch_book_description_from_goodreads(title, subtitle, author)
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
  cover_image_path = book_image_path(title)
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
  str.downcase.gsub(/[(),&:!?\/\\]/, '').gsub(/[\s_]/, '-')
end

def book_image_path(title)
  "assets/img/books/#{dasherize(title)}.jpg"
end

def other_resource_image_base_path(title, image_subfolder)
  "assets/img/#{image_subfolder}/#{dasherize(title)}"
end

def download_cover(title, cover_id, cover_image_path)
  unless cover_id
    puts "No cover image available for book '#{title}'"
    return nil
  end

  url = "https://covers.openlibrary.org/b/id/#{cover_id}-M.jpg"
  puts "Downloading cover image for book '#{title}' to '#{cover_image_path}'"
  download_image(url, 'https://covers.openlibrary.org', cover_image_path)
end

def turn_to_absolute_url(url, source_website_url)
  if url.start_with?("http")
    url
  elsif url.start_with?("//")
    "https:#{url}"
  elsif url.start_with?("/")
    source_website_uri = URI.parse(source_website_url)
    "https://#{source_website_uri.host}#{url}"
  elsif url.start_with?("../")
    URI.join(source_website_url, url).to_s
  else
    "#{source_website_url}/#{url}"
  end
end

def download_image(image_url, source_website_url, image_file_path)
  image_url = turn_to_absolute_url(image_url, source_website_url)
  download = make_http_request_with_retries(image_url)
  IO.copy_stream(download, image_file_path)
  image_file_path
end

# Ruby has no way to update YAML without completely changing the formatting, so to avoid turning outline.yaml into a
# hot mess, this is a hacky method that uses regex to insert YAML elements.
def add_element_to_outline_yaml(title, outline_as_str, element_name, element_value, value_type = :string)
  unless element_value
    puts "WARN: did not find a '#{element_name}' for '#{title}'"
    return outline_as_str
  end

  puts "Adding '#{element_name}' to YAML for '#{title}'"
  formatted_value = format_value_for_yaml(element_value, value_type)
  updated_outline = outline_as_str.gsub(/^(\s*?)(- title: "#{Regexp.escape(title)}")/, "\\1\\2\n\\1  #{element_name}: #{formatted_value}")
  if outline_as_str == updated_outline
    raise "Something went wrong with hack regex replace when updating the outline. Tried to update '#{title}' with element '#{element_name}', but there was no diff."
  end
  updated_outline
end

def format_value_for_yaml(value, value_type)
  case value_type
  when :string
    "\"#{value.gsub('"', "'").gsub("\n", " ")}\""
  when :number
    value.to_s
  else
    raise "Unsupported value type '#{value_type}' with value '#{value}'"
  end
end

def process_books(chapter, outline_as_str)
  books = chapter['books'] || []

  books.each do |book|
    title = book['title']
    subtitle = book['subtitle']
    author = book['author']
    image = book['image']
    image_width = book['image_width']
    image_height = book['image_height']
    description = book['description']

    if description
      puts "Book '#{title}' already has a description. Will not try to update it."
    else
      description = fetch_book_description_from_open_library(title, subtitle, author) || fetch_book_description_from_goodreads(title, subtitle, author)
      outline_as_str = add_element_to_outline_yaml(title, outline_as_str, 'description', description)
    end

    if image
      puts "Book '#{title}' already has an image. Will not try to update it."
    else
      image_file_path = fetch_book_cover_image_from_open_library(title, author, description)
      outline_as_str = add_element_to_outline_yaml(title, outline_as_str, 'image', image_file_path)
    end

    if image_width && image_height
      puts "Book '#{title}' already has an image width and height. Will not try to update it."
    elsif image
      image_width, image_height = get_image_dimensions(image)
      outline_as_str = add_element_to_outline_yaml(title, outline_as_str, 'image_height', image_height, :number)
      outline_as_str = add_element_to_outline_yaml(title, outline_as_str, 'image_width', image_width, :number)
    else
      puts "Book '#{title}' has no image, so can't fill in image width and height."
    end
  end

  outline_as_str
end

def get_image_dimensions(image_file_path)
  image = MiniMagick::Image.open(image_file_path)
  return image.width, image.height
end

def extract_description_from_doc(doc)
  doc.at('meta[property="og:description"]')&.[]('content') ||
    doc.at('meta[property="twitter:description"]')&.[]('content') ||
    doc.at('meta[name="description"]')&.[]('content') ||
    doc.at('title')&.text # Fall back to page title
end

def get_image_url_for_doc(doc, url)
  if url.include?("youtube.com") || url.include?("youtu.be")
    video_id = url[/v=([^&]+)/, 1] || url.split('/').last
    "https://img.youtube.com/vi/#{video_id}/hqdefault.jpg"
  elsif url.include?("vimeo.com")
    video_id = url.split('/').last
    vimeo_api_url = "https://vimeo.com/api/v2/video/#{video_id}.json"
    json_data = JSON.parse(make_http_request_with_retries(vimeo_api_url).read)
    json_data.first["thumbnail_large"]
  else
    doc.at('meta[property="og:image"]')&.[]('content')&.strip ||
      doc.at('meta[property="twitter:image"]')&.[]('content')&.strip
  end
end

$image_extensions = %w[png jpg jpeg gif]

def check_if_image_exists_given_base_path(image_base_path)
  Dir.glob("#{image_base_path}.{#{$image_extensions.join(',')}}").first
end

def get_image_extension_from_image_url(image_url)
  ext = File.extname(URI.parse(image_url).path)
  if ext.empty?
    puts "WARN: no file extension on '#{image_url}', so falling back to a guess of JPG"
    ".jpg"
  else
    ext
  end
end

def fetch_image_for_doc(doc, url, title, image_subfolder)
  image_base_path = other_resource_image_base_path(title, image_subfolder)
  if image_path = check_if_image_exists_given_base_path(image_base_path)
    puts "Already have an image for other resource '#{title}' at '#{image_path}', will not download again"
    return image_path
  end

  image_url = get_image_url_for_doc(doc, url)
  if image_url
    image_extension = get_image_extension_from_image_url(image_url)
    image_path = "#{image_base_path}#{image_extension}"
    puts "Downloading image for other resource '#{title}' from '#{image_url}' to '#{image_path}'"
    begin
      download_image(image_url, url, image_path)
      return resize_image(image_path)
    rescue => error
      if error.message.include?("404 Not Found")
        puts "WARN: Got a 404 when trying to download image for '#{title}' from '#{image_url}'. Will fall back to screenshot."
      else
        raise error
      end
    end
  end

  # Fall back to screenshot
  image_path = "#{image_base_path}.png"
  capture_screenshot(url, image_path)
  resize_image(image_path)
end

def capture_screenshot(url, image_path)
  puts "Taking screenshot of page at '#{url}' and writing to '#{image_path}'"

  options = Selenium::WebDriver::Chrome::Options.new
  options.add_argument('--headless')
  options.add_argument('--window-size=1280,800')

  driver = Selenium::WebDriver.for :chrome, capabilities: [options]

  begin
    driver.navigate.to url
    sleep 3  # Wait for the page to load
    driver.save_screenshot(image_path)
  ensure
    driver.quit  # Close the browser
  end

  image_path
end

$resizable_extensions = %w[.jpg .jpeg .png .gif]

def resize_image(image_path)
  unless $resizable_extensions.include?(File.extname(image_path))
    puts "WARN: Image '#{image_path}' is not one I know how to resize, so skipping."
    return image_path
  end

  begin
  image = MiniMagick::Image.open(image_path)
  image.resize "180x"
  image.write(image_path)
  rescue => error
    puts "WARN: failed to resize image at '#{image_path}' due to error: '#{error}'"
  end

  image_path
end

$domains_to_skip = %w[akamai.com microsoft.com oracle.com godaddy.com entrust.com mysql.com servicenow.com rootly.com codacy.com chatgpt.com openai.com llama.com midjourney.com reversinglabs.com ox.security]

def should_skip(title, url)
  # These are domains known not to work with scripting (some sort of user agent blocking or bot detection), so we skip
  # them. You'll have to put these entries into the outline manually.
  $domains_to_skip.each do |domain_to_skip|
    if url.include?(domain_to_skip)
      return true
    end
  end

  false
end

def find_image_and_descriptions_for_resource(resource, resource_type, image_subfolder, outline_as_str)
  title = resource['title']
  url = resource['url']
  image = resource['image']
  description = resource['description']
  image_width = resource['image_width']
  image_height = resource['image_height']

  if description && image
    puts "#{resource_type} '#{title}' already has a description and image. Will not try to update them."
  elsif should_skip(title, url)
    puts "WARN: #{resource_type} '#{title}' at URL '#{url}' is on the to skip list. Will not process. You'll have to fill this one in manually."
  else
    html = make_http_request_with_retries(url).read
    doc = Nokogiri::HTML(html)

    if description
      puts "#{resource_type} '#{title}' already has a description. Will not try to update it."
    else
      description = extract_description_from_doc(doc)
      outline_as_str = add_element_to_outline_yaml(title, outline_as_str, 'description', description)
    end

    if image
      puts "#{resource_type} '#{title}' already has an image. Will not try to update it."
    else
      image = fetch_image_for_doc(doc, url, title, image_subfolder)
      outline_as_str = add_element_to_outline_yaml(title, outline_as_str, 'image', image)
    end
  end

  if image_width && image_height
    puts "#{resource_type} '#{title}' already has an image width and height. Will not try to update it."
  elsif image
    image_width, image_height = get_image_dimensions(image)
    outline_as_str = add_element_to_outline_yaml(title, outline_as_str, 'image_height', image_height, :number)
    outline_as_str = add_element_to_outline_yaml(title, outline_as_str, 'image_width', image_width, :number)
  else
    puts "#{resource_type} '#{title}' has no image, so can't fill in image width and height."
  end

  outline_as_str
end


def process_other_resources(chapter, outline_as_str)
  other_resources = chapter['other_resources'] || []

  other_resources.each do |other_resource|
    outline_as_str = find_image_and_descriptions_for_resource(other_resource, "Other resource", "other-resources", outline_as_str)
  end

  outline_as_str
end

def process_tools(chapter, outline_as_str)
  tools = chapter['tools'] || []

  tools.each do |tool_category|
    tool_type = tool_category['type']
    tools = tool_category['tools']

    tools.each do |tool|
      outline_as_str = find_image_and_descriptions_for_resource(tool, "Tool #{tool_type}", "tools", outline_as_str)
    end
  end

  outline_as_str
end

def process_outline(outline, outline_as_str, max_chapters_to_process)
  begin
    chapters_processed = 0
    outline.each do |chapter|
      outline_as_str = process_books(chapter, outline_as_str)
      outline_as_str = process_other_resources(chapter, outline_as_str)
      outline_as_str = process_tools(chapter, outline_as_str)

      chapters_processed +=1

      if max_chapters_to_process && chapters_processed >= max_chapters_to_process
        raise "Processed max allowed chapters (#{max_chapters_to_process}). Will not process any more."
      end
    end
  rescue => error
    # Catch all errors, but return the outline at the end anyway so as to save progress
    puts "ERROR: Caught error while processing outline: #{error}"
    puts error.backtrace
  end

  outline_as_str
end

outline_file_path = '_data/outline.yml'
outline = YAML.load_file(outline_file_path)
outline_as_str = File.read(outline_file_path)

# Set to nil to process all chapters
max_chapters_to_process = nil

updated_outline_as_str = process_outline(outline, outline_as_str, max_chapters_to_process)
puts "Updating '#{outline_file_path}'"
File.write(outline_file_path, updated_outline_as_str)