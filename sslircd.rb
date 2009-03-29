# Contributer: Michael.Guymon 
# URL http://code.google.com/u/michael.guymon/
#
# Example for running ircd with ssl enabled.
# requires rsa.key and cert.pem to be created by the administrator.

require 'ircd'
require 'ircclient'
require 'netutils'
require 'openssl'

include NetUtils

begin  
    pkey = OpenSSL::PKey::RSA.new(File.open("rsa.key").read) 
    cert = OpenSSL::X509::Certificate.new(File.open("cert.pem").read)  

    s = IRCServer.new( :Port => 6679, 
                      :Logger => WEBrick::BasicLog::new('devrcd.log', WEBrick::Log::DEBUG),
                      :SSLEnable => true,
                      :SSLVerifyClient => OpenSSL::SSL::VERIFY_NONE,
                      :SSLCertificate => cert,
                      :SSLPrivateKey => pkey,
                      :SSLCertName => [ [ "CN",WEBrick::Utils::getservername ] ] )

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

rescue Exception => e
    p e
    carp e
end
