#!/usr/local/bin/ruby
require 'thread'
require 'synchronized_store'
require 'irc_server'
require 'irc_channel'
require 'ircreplies'
require 'irc_client'

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

class UserStore < SynchronizedStore
  def <<(client)
      self[client.nick] = client
  end
  alias nicks keys
  alias each_user each_value 
end
class ChannelStore < SynchronizedStore 
    def add(c)
        self[c] ||= IRCChannel.new(c)
    end

    def remove(c)
        self.delete[c]
    end
    
    alias each_channel each_value 
    alias channels keys
end
$channel_store = ChannelStore.new

if __FILE__ == $0
    #require 'irc_client_service'
    s = IRCServer.new( :Port => $config['port'] )
    begin
        while arg = ARGV.shift
            case arg
            when /-v/
                $verbose = true
            end
        end
        trap("INT"){ 
            s.carp "killing #{$$}"
            system("kill -9 #{$$}")
            s.shutdown
        }
        p = Thread.new {
            s.do_ping()
        }
        
        #s.addservice('serviceclient',IrcClientService::TestActor)
        s.start

        #p.join
    rescue Exception => e
        s.carp e
    end
end
