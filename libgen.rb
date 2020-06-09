#!/usr/bin/ruby

require 'net/http'
require 'net/https'
require 'uri'
require 'open-uri'

require 'nokogiri'
require 'unirest'
require 'lisbn'
require 'http'
require 'tty-logger'

class String
  def to_a
    [self]
  end
end

class BookDownloader
  def initialize
    @LOG = TTY::Logger.new
    @BOOK_HOST_LIST = {
      'LIBGEN' => { 'host' => 'http://93.174.95.29', 'path' => '/main/%{md5}' },
      'GENLIB' => {
        'host' => 'https://libgen.lc', 'path' => '/ads.php?md5=%{md5}'
      },
      'BOOKSCR' => {
        'host' => 'http://booksdescr.org', 'path' => '/ads.php?md5=%{md5}'
      },
    }


    @BOOK_API_FIELDS = %w[
      aich
      asin
      author
      bookmarked
      city
      cleaned
      color
      commentary
      coverurl
      crc32
      ddc
      doi
      dpi
      edition
      edonkey
      extension
      filesize
      generic
      googlebookid
      id
      identifier
      issn
      issue
      language
      lbc
      lcc
      library
      local
      locator
      md5
      openlibraryid
      orientation
      pages
      paginated
      periodical
      publisher
      scanned
      searchable
      series
      sha1
      timeadded
      timelastmodified
      title
      topic
      tth
      udc
      visible
      volumeinfo
      year
    ]
    @f_archive = File.join(__dir__, '/DOWNLOADER_LIBGEN_ARCHIVE.txt')
    @archive = File.exist?(@f_archive) ? File.read(@f_archive).split("\n") : []
  end

  def smart_truncate(text, char_limit = 80, char = ' ')
    size = 0
    text.split(char).reject do |token|
      size += token.size + 1
      size > char_limit
    end.join(' ') +
      (text.size > char_limit ? ' ' + '...' : '')
  end

  def include_in_archive(md5)
    out = File.open(@f_archive, 'a')
    out.puts md5
    out.close
  end

  def book_download_url(url, filename, directory = 'g:/Documents/Books/LIBGEN')
    return 0 if url.nil? || url.empty?

    @LOG.debug('FILE_DOWNLOADER', url)
    system(
      [
        'aria2c', '-c', '--summary-interval=30', '--show-console-readout false', '-x 16', '-s 16', "--dir=\"#{directory}\"", "--out=\"#{filename}\"", "\"#{url}\""
      ].join(' ')
    ) # `#{["aria2c.exe", "-c", "-x 16", "-s 16", "-q", "--dir=\"#{directory}\"", "--out=\"#{filename}\"", url].join(" ")}`
  end

  def book_file_write(data, filename, directory = 'g:/Documents/Books/LIBGEN')
    output = File.join(directory, filename)
    return 0 if File.exist?(output)

    @LOG.debug('FILE_WRITER', filename)
    out = File.open(output, 'w')
    out.write data
    out.close
  end

  def book_api_host
    'http://gen.lib.rus.ec'
  end

  def book_download_webpage(host_name, md5)
    host = @BOOK_HOST_LIST[host_name]
    host['host'] + host['path'] % { md5: md5 }
  end

  def book_api_path_json(md5)
    '/json.php?ids=' + md5 + '&fields=' + @BOOK_API_FIELDS.join(',')
  end

  def book_api_path_bib(md5)
    '/book/bibtex.php?md5=' + md5
  end

  def book_json_get(md5)
    @LOG.debug('API_FETCH_JSON', " => #{md5}")
    begin
      uri = URI.parse(book_api_host)
      http = Net::HTTP.new(uri.host, uri.port)
      request = Net::HTTP::Get.new(book_api_path_json(md5))
      response = http.request(request)

      return JSON.parse(response.body)
    rescue => e
      @LOG.error(
        'API_FETCH_JSON',
        'ERROR encountered while fetching json from ' + book_api_host
      )
      print response.body
      puts e.backtrace.join("\n")
      return []
    end
  end

  def book_bibtex_get(md5)
    @LOG.debug('API_FETCH_BIBTEX', "=> #{md5}")
    begin
      uri = URI.parse('http://gen.lib.rus.ec')
      http = Net::HTTP.new(uri.host, uri.port)
      request = Net::HTTP::Get.new(book_api_path_bib(md5))
      response = http.request(request)
      return response.body
    rescue => e
      @LOG.error(
        'API_FETCH_BIBTEX',
        'ERROR encountered while fetching json from ' + book_api_host
      )
      puts e.backtrace.join("\n")
      return []
    end
  end

  def book_webpage_get(md5, hostlist)
    p hostlist
    @LOG.debug('WEB_FETCH_PAGE', "=> #{md5}")
    host = hostlist.shift
    begin
      @LOG.info('WEB_FETCH_PAGE', "=> HOST Selected #{host}")
      url = book_download_webpage(host, md5) #   ].join(' ')

      # response = http.request(request)
      # return { body: response.body, host: url_data['host'] }
      puts "1 => #{url}"
      response = HTTP.headers(:USER_AGENT => "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/81.0.4044.83 Safari/537.36")
                     .get(url).to_s
      # uri = URI.parse(url)
      # http = Net::HTTP.new(uri.host, uri.port)
      # request = Net::HTTP::Get.new(uri)
      # request['User-Agent'] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/81.0.4044.83 Safari/537.36"
      # response = http.request(request).body
      # p response
      return { body: response, host: @BOOK_HOST_LIST[host]['host'] }
    rescue => e
      @LOG.error(
        'WEB_FETCH_PAGE',
        'ERROR encountered while fetching webpage from ' + host
      )
      puts e.backtrace.join("\n")
      return book_webpage_get(md5, hostlist) if !hostlist.empty?
      puts "HOST LIST EMPTY" if hostlist.empty?
    end
  end

  def book_metadata_parse(doc)
    page = Nokogiri::HTML.parse(doc[:body])

    book_url = page.at('a')['href']
    cover_url = page.at('img')['src']

    {
      'book' => /^http/ === book_url ? book_url : doc[:host] + book_url,
      'cover' => /^http/ === cover_url ? cover_url : doc[:host] + cover_url
    }
  end

  def book_name_format(json)
    json_hash = {}
    json.keys.each do |key|
      if key == 'identifier'
        isbn = json[key].scan(/[\d\-X]+/).map { |e| e.gsub('-', '') }
                        .select { |e| Lisbn.new(e).valid? }
        json_hash[key.to_sym] = isbn.empty? ? 'NA' : Lisbn.new(isbn.first).isbn13
      elsif key == 'title'
        json_hash[key.to_sym] =
          json[key].empty? ? 'NA' : smart_truncate(json[key], 82)
      elsif key == 'author'
        if json[key].empty?
          json_hash[key.to_sym] = 'NA'
        else
          author = json[key].split(', ')[0..3]
          author << '...' if json[key].split(', ').length > 3
          json_hash[key.to_sym] =
            if json[key].empty?
              'NA'
            else
              smart_truncate(author.flatten.join(', '), 82,  ', ')
            end
        end
      else
        json_hash[key.to_sym] = json[key].empty? ? 'NA' : json[key]
      end
    end

    ('[%{author}]_%{title}_(%{year})_[%{identifier}]' % json_hash).gsub(
      %r{[\x00\/\\:\*\?\"<>\|]},
      ' - '
    ).gsub(/\s{2,}/, ' ')
  end

  def book_details_get(md5 = '096853F68B429CED1C722D409E7C87F1')
    @LOG.info('BOOK_DOWNLOADER', "=> #{md5}")

    book_json = book_json_get(md5).first
    filename_ext = book_name_format(book_json)

    filename = filename_ext + '.' + book_json['extension']
    cover_file = filename_ext + '.jpg'
    json_file = filename_ext + '.json'
    bibtex_file = filename_ext + '.bib'

    book_page = book_webpage_get(md5, @BOOK_HOST_LIST.keys)
    book_meta = book_metadata_parse(book_page)
    book_bibtex_page = book_bibtex_get(md5)
    book_bibtex = Nokogiri::HTML.parse(book_bibtex_page).at('textarea').text

    {
      'json' => {
        'application' => 'LIBGen',
        'timestamp' => Time.now.to_i,
        'data' => {
          'json' => book_json,
          'bibtex' => book_bibtex,
          'cover_url' => book_meta['cover'],
          'file_url' => book_meta['book']
        }
      }.to_json,
      'bibtex' => book_bibtex,
      'filename_ext' => filename_ext,
      'files' => {
        'name' => filename,
        'cover' => cover_file,
        'json' => json_file,
        'bibtex' => bibtex_file
      },
      'book' => book_meta['book'],
      'cover' => book_meta['cover']
    }
  end

  def book_downloader(md5_list)
    md5_list = md5_list.to_a if md5_list.class == String
    raise "invalid argument type #{md5}" if md5_list.class != Array

    md5_list.each do |md5|
      if @archive.include? md5
        @LOG.info(
          'LIBGEN_DOWNLOADER',
          "Skip download for #{md5}, already downloaded"
        )
      end
      next if @archive.include? md5

      begin
        book_details = book_details_get(md5)

        book_file_write(book_details['json'], book_details['files']['json'])
        # book_file_write(book_details['bibtex'], book_details['files']['bibtex'])
        book_download_url(book_details['book'], book_details['files']['name'])
        book_download_url(book_details['cover'], book_details['files']['cover'])

        include_in_archive(md5)
        return true
      rescue => e
        @LOG.error('LIBGEN_DOWNLOADER', "failed to download book #{md5}")
        puts e.backtrace.join("\n")
        return false
      end
    end
  end
end
