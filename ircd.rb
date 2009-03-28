#!/usr/local/bin/ruby
require 'thread'
require 'synchronized_store'
require 'irc_server'
require 'irc_channel'
require 'ircreplies'
require 'irc_client'
require 'irc_daemon'

include IRCReplies

$config ||= {}
$config['version'] = '0.04dev'
$config['timeout'] = 10
$config['port'] = 6667
$config['hostname'] = Socket.gethostname.split(/\./).shift
$config['starttime'] = Time.now.to_s
$config['nick-tries'] = 5

$verbose = ARGV.shift || false
    
CHANNEL = /^[#\$&]+/
PREFIX  = /^:[^ ]+ +(.+)$/


if __FILE__ == $0
  IRCDaemon.new
end
