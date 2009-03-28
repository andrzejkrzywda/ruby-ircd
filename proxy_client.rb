class ProxyClient < IRCClient

    def initialize(nick, actor, serv)
        carp "Initializing service #{nick}"
        @nick = nick
        super(nil,serv)
        @conn = IrcClient::ProxyConnector.new(nick,'pass',self,actor)
    end

    def peer
        return @nick
    end

    def handle_connect
        @conn.connect
    end

    def getnick(user)
        if user =~ /^:([^!]+)!.*/
            return $1
        else
            return user
        end
    end

    def reply(method, *args)
        puts "reply: #{method}, args: #{args}"
        case method
        when :raw
            arg = *args
            @conn.invoke :unknown, arg
        when :ping
            host = *args
            @conn.invoke :ping, host
        when :pong
            msg = *args
            @conn.invoke :pong, msg
        when :join
            user,channel = args
            @conn.invoke :join, getnick(user), channel
        when :privmsg
            user, channel, msg = args
            @conn.invoke :privmsg, getnick(user), channel, msg
        when :notice
            user, channel, msg = args
            @conn.invoke :notice, getnick(user), channel, msg
        when :topic
            user, channel, msg = args
            @conn.invoke :topic, getnick(user), channel, msg
        when :nick
            nick = *args
            @conn.invoke :nick, nick
        when :mode
            nick, rest = args
            @conn.invoke :mode, nick, rest
        when :numeric
            numeric,msg,detail = args
            server = $config['hostname']
            @conn.invoke :numeric, server, numeric, msg, detail
        end
    end

    #From the local services
    def invoke(method, *args)
        case method
        when :pong
            server = *args
            handle_pong server
        when :pass
            pass = *args
            handle_pass pass
        when :nick
            nick = *args
            handle_nick nick
        when :user
            user, mode, vhost, realname = args
            handle_user user, mode, vhost, realname
        when :names
            channel, serv = *args
            handle_names channel, serv
        when :join
            channel = *args
            handle_join channel
        when :part
            channel, msg = args
            handle_part channel, msg
        when :quit
            msg = args
            handle_quit msg
        when :privmsg
            channel, msg = args
            handle_privmsg channel, msg
        else
            handle_unknown "#{method} #{args.join(',')}"
        end
    end
end

