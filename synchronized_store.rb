class SynchronizedStore
    def initialize
        @store = {}
        @mutex = Mutex.new
    end
    
    def method_missing(name,*args)
        @mutex.synchronize { @store.__send__(name,*args) }
    end

    def each_value
        @mutex.synchronize do
            @store.each_value {|u|
                @mutex.unlock
                yield u
                @mutex.lock
            }
        end
    end

    def keys
        @mutex.synchronize{@store.keys}
    end
end
