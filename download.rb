#!/usr/bin/ruby
# frozen_string_literal: true

require_relative 'libgen'

downloader = BookDownloader.new
downloader.book_downloader(File.read('libgen.txt').split("\n"))
