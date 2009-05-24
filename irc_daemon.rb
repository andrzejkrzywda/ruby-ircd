class IRCDaemon
  def initialize

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
end
