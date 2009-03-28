module IrcClient
    require 'timeout'
    require "socket"
    require 'thread'
    require 'ircreplies'
    require 'netutils'

    include IRCReplies

    # The irc class, which talks to the server and holds the main event loop
    class IrcActor
        include NetUtils
        attr_reader :channels
        #=========================================================== 
        #events
        #=========================================================== 
        def initialize(client)
            @client = client
            @eventqueue = ConditionVariable.new
            @eventlock = Mutex.new
            @events = []
            @channels = {}
            @store = {
                :ping => 
                Proc.new {|server|
                    client.send_pong server
                },
                :pong => 
                Proc.new {|server|
                    puts "pong:#{server}"
                },
                :notice=>
                [Proc.new {|user,channel,msg|
                    puts "Server:#{msg}"
                    #client.msg_channel channel,"message from #{user} on #{channel} : #{msg}"
                }],
                :privmsg =>
                [Proc.new {|user,channel,msg|
                    #puts "message from #{user} on #{channel} : #{msg}"
                    #client.msg_channel channel,"message from #{user} on #{channel} : #{msg}"
                }],
                :connect =>
                [Proc.new {|server,port,nick,pass|
                    #puts "on connect #{server}:#{port}"
                    client.send_pass pass
                    client.send_nick nick
                    client.send_user nick,'0','*',"#{server} Net Bot"
                }],
                :numeric =>
                [Proc.new {|server,numeric,msg,detail|
                    #puts "on numeric #{server}:#{numeric}"
                }],
                :join=>
                [Proc.new {|nick,channel|
                    #puts "on join"
                }],
                :part=>
                [Proc.new {|nick,channel,msg|
                    #puts "on part"
                }],
                :quit=>
                [Proc.new {|nick,msg|
                    #puts "on quit"
                }],
                :unknown =>
                [Proc.new {|line|
                    puts ">unknown message #{line}"
                }]
            }
        end
        
        #=========================================================== 
        #on_xxx appends to registered callbacks
        #use [] to reset callbacks
        #=========================================================== 
        def on_connect(&block)
            raise IrcError.new('wrong arity') if block.arity != 4
            self[:connect] << block
        end

        def on_ping(&block)
            raise IrcError.new('wrong arity') if block.arity != 1
            self[:ping] << block
        end

        def on_privmsg(&block)
            raise IrcError.new('wrong arity') if block.arity != 3
            self[:privmsg] << block
        end

        def on_numeric(numarray,&block)
            raise IrcError.new('wrong arity') if block.arity != 4
            self[:numeric] << Proc.new {|server,numeric,msg,detail|
                case numeric
                when *numarray
                    block.call(server,numeric,msg,detail)
                end
            }
        end

        def on_rpl(num,&block)
            raise IrcError.new('wrong arity') if block.arity != 3
            self[:numeric] << Proc.new {|server,numeric,msg,detail|
                block.call(server,msg,detail) if num == numeric
            }
        end

        def on_err(num,&block)
            on_rpl(num,block)
        end

        def on(method,&block)
            self[method] << block
        end

        #=========================================================== 
        def [](method)
            @store[method] = [] if @store[method].nil?
            return @store[method]
        end

        def push(method,*args)
            @eventlock.synchronize {
                @events << [method,args]
                @eventqueue.signal
            }
        end
        
        def send_names(channel)
            @client.send_names channel
            channel
        end

        def send_message(user,message)
            @client.msg_user user, message
            user
        end
        
        def send(message)
            @client.send message
            message
        end

        def run
            while true
                begin
                    method,args = :unknown,''
                    @eventlock.synchronize {
                        @eventqueue.wait(@eventlock) if @events.empty?
                        method,args = @events.shift
                    }
                    self[method].each {|block| block[*args] }
                rescue SystemExit => e
                    exit 0
                rescue Exception => e
                    carp e
                end
            end
        end

        def join(channel)
            @client.send_join channel
            @channels[channel] = Time.now
            channel
        end

        def part(channel)
            if @channels.delete(channel)
                @client.send_part channel
                channel
            else
                'not member'
            end
        end

        def nick
            return @nick
        end

        def names(channel)
            return @client.names(channel)
        end 
        
    end

    class PrintActor < IrcActor
        def initialize(client)
            super(client)
            on(:connect) {|server,port,nick,pass|
                client.send_join '#db'
            }
            on(:numeric) {|server,numeric,msg,detail|
                #puts "-:#{numeric}"
            }
            on(:join) {|nick,channel|
                #puts "#{nick} join-:#{channel}"
                #client.msg_channel '#markee', "heee"
            }
            on(:part) {|nick,channel,msg|
                #puts "#{nick} part-:#{channel}"
            }
            on(:quit) {|nick,msg|
                #puts "#{nick} quit-:#{channel}"
            }
        end
    end
    class TestActor < IrcActor
        def initialize(client)
            super(client)
            on(:connect) {|server,port,nick,pass|
                client.send_join '#db'
            }
            on(:numeric) {|server,numeric,msg,detail|
                puts "-:#{numeric}"
            }
            on(:join) {|nick,channel|
                puts "#{nick} join-:#{channel}"
            }
            on(:part) {|nick,channel,msg|
                puts "#{nick} part-:#{channel}"
            }
            on(:quit) {|nick,msg|
                puts "#{nick} quit-:#{nick}:#{msg}"
            }
            on(:privmsg) {|nick,channel,msg|
                case msg
                when /^ *!who +([^ ]+) *$/
                    names = names($1)
                    send_message channel, "names: #{names.join(',')}"
                end
            }
        end
    end

    class IrcConnector
        include IRCReplies
        include NetUtils
        extend NetUtils

        attr_reader :server, :port, :nick, :socket
        attr_writer :actor, :socket

        def initialize(server, port, nick, pass)
            @server = server
            @port = port
            @nick = nick
            @pass = pass
            @actor = IrcActor.new(self)
            @readlock = Mutex.new
            @writelock = Mutex.new


            @inputlock = Mutex.new
            @inputqueue = ConditionVariable.new
        end

        def run
            connect()
            @eventloop = Thread.new { @actor.run }
            listen_loop
        end

        def connect()
            begin
                #allow socket to be handed over from elsewhere.
                @socket = @socket || TCPSocket.open(@server, @port)
                @actor[:connect].each{|c| c[ @server, @port, @nick, @pass]}
            rescue
                raise "Cannot connect #{@server}:#{@port}"
            end
        end
       
        #=========================================================== 
        def process(input)
            input.untaint
            s = input
            prefix = ''
            user = ''
            if input =~ /^:([^ ]+) +(.*)$/
                s = $2
                prefix = $1
                user = if prefix =~ /^([^!]+)!(.+)/
                           $1
                       else
                           prefix
                       end
            end

            cmd = s
            suffix = ''
            if s =~ /([^:]+):(.*)$/
                cmd = $1.strip
                suffix = $2
            end
            case cmd
            when /^PING$/i
                #dont bother about event loop here.
                @actor[:ping][suffix]
            when /^PONG$/i
                @actor[:pong][suffix]
            when /^NOTICE +(.+)$/i
                @actor.push :notice, user, $1, suffix
            when /^PRIVMSG +(.+)$/i
                @actor.push :privmsg, user, $1, suffix
            when /^JOIN$/i
                #the confirmation join channel will come in suffix
                @actor.push :join, user, suffix
            when /^PART +(.+)$/i
                #the confirmation part channel will come in cmd arg.
                @actor.push :part, user, $1, suffix
            when /^QUIT$/i
                @actor.push :quit, user, suffix
            when /^([0-9]+) +(.+)$/i
                server,numeric,msg,detail = prefix, $1.to_i,$2, suffix
                @actor.push :numeric, server,numeric,msg,detail if !local_numeric(numeric,msg,detail)
            else
                @actor.push :unknown, input
            end
        end

        def listen_loop()
            process(gets) while !@socket.eof?
        end

        #WARNING: UGLY HACK. 
        def local_numeric(numeric,msg,detail)
            if @capture_numeric
                case numeric
                when ERR_NOSUCHNICK
                    if msg =~ / *[^ ]+ +([^ ]+)*$/
                        if $1 == @capture_channel
                            @inputlock.synchronize {
                                @args << [numeric,msg,detail]
                                @inputqueue.signal
                            }
                            return true
                        end
                    end
                when RPL_ENDOFNAMES
                    if msg =~ / *[^ ]+ +([^ ]+)*$/
                        if $1 == @capture_channel
                            @inputlock.synchronize {
                                @args << [numeric,msg,detail]
                                @inputqueue.signal
                            }
                            return true
                        end
                    end
                when RPL_NAMREPLY
                    if msg =~ / *[^ ]+ *= +([^ ]+)*$/
                        if $1 == @capture_channel
                            @inputlock.synchronize {
                                @args << [numeric,msg,detail]
                                @inputqueue.signal
                            }
                            return true
                        end
                    end
                end
            end
            return false #continue with processing
        end

        #will be invoked from a thread different from that of the
        #primary IrcConnector thread.
        def names(channel)
            carp "invoke names for #{channel}"
            @names = []
            @args = []
            @capture_channel = channel.chomp
            @capture_numeric = true
            send_names channel
            while true
                numeric, msg, detail = 0,'',''
                @inputlock.synchronize {
                    @inputqueue.wait(@inputlock) if @args.empty?
                    numeric, msg, detail = @args.shift
                }
                case numeric
                when ERR_NOSUCHNICK
                    carp ERR_NOSUCHNICK
                    break
                when RPL_ENDOFNAMES
                    carp "#{RPL_ENDOFNAMES} #{@names}"
                    break
                when RPL_NAMREPLY
                    nicks = detail.split(/ +/)
                    nicks.each {|n| @names << $1.strip if n =~ /^@?([^ ]+)/ }
                    carp "nicks #{nicks}"
                end
            end
            carp "returning #{@names}"
            @capture_numeric = false
            return @names
        end

        #=====================================================
        def lock_read
            @readlock.lock
        end

        def unlock_read
            @readlock.unlock
        end

        def lock_write
            @writelock.lock
        end

        def unlock_write
            @writelock.unlock
        end
        #=====================================================
        def send_pong(arg)
            send "PONG :#{arg}"
        end

        def send_pass(pass)
            send "PASS #{pass}"
        end

        def send_nick(nick)
            send "NICK #{nick}"
        end

        def send_user(user,mode,unused,real)
            send "USER #{user} #{mode} #{unused} :#{real}"
        end

        def send_names(channel)
            send "NAMES #{channel}"
        end

        def send(msg)
            send "#{msg}"
        end
        #=====================================================
        def send_join(channel)
            send "JOIN #{channel}"
        end

        def send_part(channel)
            send "PART #{channel} :"
        end

        def msg_user(user,data)
            msg_channel(user, data)
        end

        def msg_channel(channel, data)
            send "PRIVMSG #{channel} :#{data}"
        end
        
        def notice_channel(channel, data)
            send "NOTICE #{channel} :#{data}"
        end

        def gets
            s = nil
            @readlock.synchronize { 
                s = @socket.gets
            }
            #carp "<#{s}"
            return s 
        end
        
        def send(s)
            #carp ">#{s}"
            @writelock.synchronize { @socket << "#{s}\n" }
        end
        #=====================================================
        def IrcConnector.start(opts={})
            server = opts[:server] or raise 'No server defined.'
            nick = opts[:nick] || '_' + Socket.gethostname.split(/\./).shift
            port = opts[:port] || 6667
            pass = opts[:pass] || 'netserver'
            irc = IrcConnector.new(server, port , nick, pass)
            #irc.actor = PrintActor.new(irc)
            irc.actor = TestActor.new(irc)
            begin
                irc.run
            rescue SystemExit => e
                puts "exiting..#{e.message()}"
                exit 0
            rescue Interrupt
                exit 0
            rescue Exception => e
                carp e
            end
        end
    end
#=====================================================
    class ProxyConnector
        attr_reader :server, :nick
        attr_writer :actor
        def initialize(nick, pass, server, actor)
            @server = 'service'
            @nick = nick
            @pass = pass
            @actor = actor.new(self)
            @ircserver = server
        end

        #=====================================================
        def invoke(method, *args)
            @actor[method].each{|c| c[*args]}
        end
        
        #called during connection.
        def connect
            @actor[:connect].each{|c| c[ @server, @port, @nick, @pass]}
        end

        def ping(arg)
            @actor[:ping].each{|c| c[arg]}
        end

        def privmsg(nick, channel, msg)
            @actor[:privmsg].each{|c| c[nick, channel, msg]}
        end

        def notice(nick, channel, msg)
            @actor[:notice].each{|c| c[nick, channel, msg]}
        end

        def join(nick, channel)
            @actor[:join].each{|c| c[nick, channel]}
        end

        def part(nick, channel, msg)
            @actor[:part].each{|c| c[nick, channel, msg]}
        end

        def quit(nick, msg)
            @actor[:quit].each{|c| c[nick, msg]}
        end

        def numeric(server,numeric,msg, detail)
            @actor[:numeric].each{|c| c[server,numeric,msg,detail]}
        end

        def unknown(arg)
            @actor[:unknown].each{|c| c[arg]}
        end
       
        #=====================================================
        def send_pong(arg)
            @ircserver.invoke :pong,arg
        end

        def send_pass(arg)
            @ircserver.invoke :pass,arg
        end

        def send_nick(arg)
            @ircserver.invoke :nick,arg
        end

        def send_user(user,mode,unused,real)
            @ircserver.invoke :user, user, mode, unused, real
        end

        def send_names(arg)
            @ircserver.invoke :names,arg
        end

        def send_join(arg)
            @ircserver.invoke :join,arg
        end

        def send_part(channel)
            @ircserver.invoke :part,arg
        end

        def msg_channel(channel, data)
            @ircserver.invoke :privmsg,channel, data
        end
        #=====================================================
        def names(channel)
            return @ircserver.names(channel)
        end

        def msg_user(user,data)
            msg_channel(user, data)
        end
    end
#=====================================================
    if __FILE__ == $0
        server = 'localhost'
        port = 6667
        nick = 'genericclient'
        while arg = ARGV.shift
            case arg
            when /-s/
                server = ARGV.shift
            when /-p/
                port = ARGV.shift
            when /-n/
                nick = ARGV.shift
            when /-v/
                $verbose = true
            end
        end
        IrcConnector.start :server => server, 
            :port => port, 
            :nick => nick, 
            :pass => 'netserver'
    end
end
