class IRCClient
    include NetUtils

    attr_reader :nick, :user, :realname, :channels, :state

    def initialize(sock, serv)
        @serv = serv
        @socket = sock
        @channels = []
        @peername = peer()
        @welcomed = false
        @nick_tries = 0
        @state = {}
        carp "initializing connection from #{@peername}"
    end

    def host
        return @peername
    end

    def userprefix
        return @usermsg
    end

    def closed?
        return @socket.nil? || @socket.closed?
    end

    def ready
        #check for nick and pass
        return (!@pass.nil? && !@nick.nil?) ? true : false
    end

    def peer
        begin
            sockaddr = @socket.getpeername
            begin
                return Socket.getnameinfo(sockaddr, Socket::NI_NAMEREQD).first
            rescue 
                return Socket.getnameinfo(sockaddr).first
            end
        rescue
            return @socket.peeraddr[2]
        end
    end

    def handle_pass(s)
        carp "pass = #{s}"
        @pass = s
    end
    
    def handle_nick(s)
        carp "nick => #{s}"
        if @serv.user_store[s].nil?
            userlist = {}
            if @nick.nil?
                handle_newconnect(s)
            else
                userlist[s] = self if self.nick != s
                @serv.user_store.delete(@nick)
                @nick = s
            end

            @serv.user_store << self

            #send the info to the world
            #get unique users.
            @channels.each {|c|
                channel_store[c].each_user {|u|
                    userlist[u.nick] = u
                }
            }
            userlist.values.each {|user|
                user.reply :nick, s
            }
            @usermsg = ":#{@nick}!~#{@user}@#{@peername}"
        else
            #check if we are just nicking ourselves.
            unless @serv.user_store[s] == self
                #verify the connectivity of earlier guy
                unless @serv.user_store[s].closed?
                    reply :numeric, ERR_NICKNAMEINUSE,"* #{s} ","Nickname is already in use."
                    @nick_tries += 1
                    if @nick_tries > $config['nick-tries']
                        carp "kicking spurious user #{s} after #{@nick_tries} tries"
                        handle_abort
                    end
                    return
                else
                    @serv.user_store[s].handle_abort
                    @serv.user_store[s] = self
                end
            end
        end
        @nick_tries = 0
    end

    def handle_user(user, mode, unused, realname)
        @user = user
        @mode = mode
        @realname = realname
        @usermsg = ":#{@nick}!~#{@user}@#{@peername}"
        send_welcome if !@nick.nil?
    end

    def mode
        return @mode
    end

    def handle_newconnect(nick)
        @alive = true
        @nick = nick
        @host = $config['hostname']
        @ver = $config['version']
        @starttime = $config['starttime']
        send_welcome if !@user.nil?
    end

    def send_welcome
        if !@welcomed
            repl_welcome
            repl_yourhost
            repl_created
            repl_myinfo
            repl_motd
            repl_mode
            @welcomed = true
        end
    end

    def repl_welcome
        client = "#{@nick}!#{@user}@#{@peername}"
        reply :numeric, RPL_WELCOME, @nick, "Welcome to this IRC server #{client}"
    end

    def repl_yourhost
        reply :numeric, RPL_YOURHOST, @nick, "Your host is #{@host}, running version #{@ver}"
    end

    def repl_created
        reply :numeric, RPL_CREATED, @nick, "This server was created #{@starttime}"
    end

    def repl_myinfo
        reply :numeric, RPL_MYINFO, @nick, "#{@host} #{@ver} #{@serv.usermodes} #{@serv.channelmodes}"
    end

    def repl_bounce(sever, port)
        reply :numeric, RPL_BOUNCE ,"Try server #{server}, port #{port}"
    end

    def repl_ison(*args)
        #XXX TODO
        reply :numeric, RPL_ISON, args.to_s
    end

    def repl_away(nick, msg)
        reply :numeric, RPL_AWAY, nick, msg
    end

    def repl_unaway()
        reply :numeric, RPL_UNAWAY, @nick,"You are no longer marked as being away"
    end

    def repl_nowaway()
        reply :numeric, RPL_NOWAWAY, @nick,"You have been marked as being away"
    end

    def repl_motd()
        reply :numeric, RPL_MOTDSTART,'', "- Message of the Day"
        reply :numeric, RPL_MOTD,'',      "- Do the dance see the source"
        reply :numeric, RPL_ENDOFMOTD,'', "- End of /MOTD command."
    end

    def repl_mode()
    end


    def send_nonick(nick)
        reply :numeric, ERR_NOSUCHNICK, nick, "No such nick/channel"
    end

    def send_nochannel(channel)
        reply :numeric, ERR_NOSUCHCHANNEL, channel, "That channel doesn't exist"
    end

    def send_notonchannel(channel)
        reply :numeric, ERR_NOTONCHANNEL, channel, "Not a member of that channel"
    end

    def send_topic(channel)
        if @serv.channel_store[channel]
            reply :numeric, RPL_TOPIC,channel, "#{@serv.channel_store[channel].topic}" 
        else
            send_notonchannel channel
        end
    end

    def names(channel)
        return @serv.channel_store[channel].nicks
    end

    def send_nameslist(channel)
        c =  @serv.channel_store[channel]
        if c.nil?
            carp "names failed :#{c}"
            return 
        end
        names = []
        c.each_user {|user|
            names << c.mode(user) + user.nick if user.nick
        }
        reply :numeric, RPL_NAMREPLY,"= #{c.name}","#{names.join(' ')}"
        reply :numeric, RPL_ENDOFNAMES,"#{c.name} ","End of /NAMES list."
    end

    def send_ping()
        reply :ping, "#{$config['hostname']}"
    end

    def handle_join(channels)
        channels.split(/,/).each {|ch|
            c = ch.strip
            if c !~ CHANNEL
                send_nochannel(c)
                carp "no such channel:#{c}"
                return
            end
            channel = @serv.channel_store.add(c)
            if channel.join(self)
                send_topic(c)
                send_nameslist(c)
                @channels << c
            else
                carp "already joined #{c}"
            end
        }
    end

    def handle_ping(pingmsg, rest)
        reply :pong, pingmsg
    end

    def handle_pong(srv)
        carp "got pong: #{srv}"
    end

    def handle_privmsg(target, msg)
        case target.strip
        when CHANNEL
            channel= @serv.channel_store[target]
            if !channel.nil?
                channel.privatemsg(msg, self)
            else
                send_nonick(target)
            end
        else
            user = @serv.user_store[target]
            if !user.nil?
                if !user.state[:away].nil?
                    repl_away(user.nick,user.state[:away])
                end
                user.reply :privmsg, self.userprefix, user.nick, msg
            else
                send_nonick(target)
            end
        end
    end

    def handle_notice(target, msg)
        case target.strip
        when CHANNEL
            channel= @serv.channel_store[target]
            if !channel.nil?
                channel.notice(msg, self)
            else
                send_nonick(target)
            end
        else
            user = @ser.user_store[target]
            if !user.nil?
                user.reply :notice, self.userprefix, user.nick, msg
            else
                send_nonick(target)
            end
        end
    end

    def handle_part(channel, msg)
        if @serv.channel_store.channels.include? channel
            if @serv.channel_store[channel].part(self, msg)
                @channels.delete(channel)
            else
                send_notonchannel channel
            end
        else
            send_nochannel channel
        end
    end

    def handle_quit(msg)
        #do this to avoid double quit due to 2 threads.
        return if !@alive
        @alive = false
        @channels.each do |channel|
            @serv.channel_store[channel].quit(self, msg)
        end
        @serv.user_store.delete(self.nick)
        carp "#{self.nick} #{msg}"
        @socket.close if !@socket.closed?
    end

    def handle_topic(channel, topic)
        carp "handle topic for #{channel}:#{topic}"
        if topic.nil? or topic =~ /^ *$/
            send_topic(channel)
        else
            begin
                @serv.channel_store[channel].topic(topic,self)
            rescue Exception => e
                carp e
            end
        end
    end

    def handle_away(msg)
        carp "handle away :#{msg}"
        if msg.nil? or msg =~ /^ *$/
            @state.delete(:away)
            repl_unaway
        else
            @state[:away] = msg
            repl_nowaway
        end
    end
        
    def handle_list(channel)
        reply :numeric, RPL_LISTSTART
        case channel.strip
        when /^#/
            channel.split(/,/).each {|cname|
                c = @serv.channel_store[cname.strip]
                reply :numeric, RPL_LIST, c.name, c.topic if c
            }
        else
            #older opera client sends LIST <1000
            #we wont obey the boolean after list, but allow the listing
            #nonetheless
            @serv.channel_store.each_channel {|c|
                reply :numeric, RPL_LIST, c.name, c.topic
            }
        end
        reply :numeric, RPL_LISTEND
    end

    def handle_whois(target,nicks)
        #ignore target for now.
        return reply(:numeric, RPL_NONICKNAMEGIVEN, "", "No nickname given") if nicks.strip.length == 0
        nicks.split(/,/).each {|nick|
            nick.strip!
            user = @serv.user_store[nick]
            if user
                reply :numeric, RPL_WHOISUSER, "#{user.nick} #{user.user} #{user.host} *", "#{user.realname}"
                reply :numeric, RPL_WHOISCHANNELS, user.nick, "#{user.channels.join(' ')}"
                repl_away user.nick, user.state[:away] if !user.state[:away].nil?
                reply :numeric, RPL_ENDOFWHOIS, user.nick, "End of /WHOIS list"
            else
                return send_nonick(nick) 
            end
        }
    end

    def handle_names(channels, server)
        channels.split(/,/).each {|ch| send_nameslist(ch.strip) }
    end

    def handle_who(mask, rest)
        channel = @serv.channel_store[mask]
        hopcount = 0
        if channel.nil?
            #match against all users
            @serv.user_store.each_user {|user|
                reply :numeric, RPL_WHOREPLY ,
                    "#{user.channels[0]} #{user.userprefix} #{user.host} #{$config['hostname']} #{user.nick} H" , 
                    "#{hopcount} #{user.realname}" if File.fnmatch?(mask, "#{user.host}.#{user.realname}.#{user.nick}")
            }
            reply :numeric, RPL_ENDOFWHO, mask, "End of /WHO list."
        else
            #get all users in the channel
            channel.each_user {|user|
                reply :numeric, RPL_WHOREPLY ,
                    "#{mask} #{user.userprefix} #{user.host} #{$config['hostname']} #{user.nick} H" , 
                    "#{hopcount} #{user.realname}"
            }
            reply :numeric, RPL_ENDOFWHO, mask, "End of /WHO list."
        end
    end

    def handle_mode(target, rest)
        #TODO: dummy
        reply :mode, target, rest
    end

    def handle_userhost(nicks)
        info = []
        nicks.split(/,/).each {|nick|
            user = @serv.user_store[nick]
            info << user.nick + '=-' + user.nick + '@' + user.peer
        }
        reply :numeric, RPL_USERHOST,"", info.join(' ')
    end

    def handle_reload(password)
    end

    def handle_abort()
        handle_quit('aborted..')
    end
        
    def handle_version()
        reply :numeric, RPL_VERSION,"#{$config['version']} Ruby IRCD", ""
    end
    
    def handle_eval(s)
        reply :raw, eval(s)
    end

    def handle_unknown(s)
        carp "unknown:>#{s}<"
        reply :numeric, ERR_UNKNOWNCOMMAND,s, "Unknown command"
    end

    def handle_connect
        reply :raw, "NOTICE AUTH :#{$config['version']} initialized, welcome."
    end
    
    def reply(method, *args)
        case method
        when :raw
            arg = *args
            raw arg
        when :ping
            host = *args
            raw "PING :#{host}"
        when :pong
            msg = *args
            # according to rfc 2812 the PONG must be of
            #PONG csd.bu.edu tolsun.oulu.fi
            # PONG message from csd.bu.edu to tolsun.oulu.fi
            # ie no host at the begining
            raw "PONG #{@host} #{@peername} :#{msg}"
        when :join
            user,channel = args
            raw "#{user} JOIN :#{channel}"
        when :part
            user,channel,msg = args
            raw "#{user} PART #{channel} :#{msg}"
        when :quit
            user,msg = args
            raw "#{user} QUIT :#{msg}"
        when :privmsg
            usermsg, channel, msg = args
            raw "#{usermsg} PRIVMSG #{channel} :#{msg}"
        when :notice
            usermsg, channel, msg = args
            raw "#{usermsg} NOTICE #{channel} :#{msg}"
        when :topic
            usermsg, channel, msg = args
            raw "#{usermsg} TOPIC #{channel} :#{msg}"
        when :nick
            nick = *args
            raw "#{@usermsg} NICK :#{nick}"
        when :mode
            nick, rest = args
            raw "#{@usermsg} MODE #{nick} :#{rest}"
        when :numeric
            numeric,msg,detail = args
            server = $config['hostname']
            raw ":#{server} #{'%03d'%numeric} #{@nick} #{msg} :#{detail}"
        end
    end
    
    def raw(arg, abrt=false)
        begin
        carp "--> #{arg}"
        @socket.print arg.chomp + "\n" if !arg.nil?
        rescue Exception => e
            carp "<#{self.userprefix}>#{e.message}"
            #puts e.backtrace.join("\n")
            handle_abort()
            raise e if abrt
        end
    end
end
