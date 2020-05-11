#!/usr/bin/ruby
# @Author: Aakash Gajjar
# @Date:   2019-06-24 07:46:43
# @Last Modified by:   Sky
# @Last Modified time: 2019-06-24 07:47:21

require_relative "libgen"

downloader = BookDownloader.new
downloader.book_downloader(File.read("libgen.txt").split("\n"))
