class IRCChannel < SynchronizedStore
    include NetUtils
    attr_reader :name, :topic
    alias each_user each_value 

    def initialize(name)
        super()

        @topic = "There is no topic"
        @name = name
        @oper = []
        carp "create channel:#{@name}"
    end

    def add(client)
        @oper << client.nick if @oper.empty? and @store.empty?
        self[client.nick] = client
    end
    
    def remove(client)
        delete(client.nick)
    end

    def join(client)
        return false if is_member? client
        add client
        #send join to each user in the channel
        each_user {|user|
            user.reply :join, client.userprefix, @name
        }
        return true
    end

    def part(client, msg)
        return false if !is_member? client
        each_user {|user|
            user.reply :part, client.userprefix, @name, msg
        }
        remove client
        return true
    end

    def quit(client, msg)
        #remove client should happen before sending notification
        #to others since we dont want a notification to ourselves
        #after quit.
        remove client
        each_user {|user|
            user.reply :quit, client.userprefix, @name, msg if user!= client
        }
    end

    def privatemsg(msg, client)
        each_user {|user|
            user.reply :privmsg, client.userprefix, @name, msg if user != client
        }
    end

    def notice(msg, client)
        each_user {|user|
            user.reply :notice, client.userprefix, @name, msg if user != client
        }
    end

    def topic(msg=nil,client=nil)
        return @topic if msg.nil?
        @topic = msg
        each_user {|user|
            user.reply :topic, client.userprefix, @name, msg
        }
        return @topic
    end

    def nicks
        return keys
    end

    def mode(u)
        return @oper.include?(u.nick) ? '@' : ''
    end

    def is_member?(m)
        values.include?(m)
    end

    alias has_nick? is_member?
end

