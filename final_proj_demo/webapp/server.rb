require 'rubygems'
require 'bundler/setup'

require 'sequel'
require 'sinatra'
require 'logger'
require 'openssl'

module USER_DB
  module DB
    def self.db_file
      'user.db'
    end

    def self.conn
      @conn ||= Sequel.sqlite(db_file,  :logger => Logger.new('db.log'))
    end

    def self.init
      return if File.exists?(db_file)
      File.umask(0066)

      conn.create_table(:users) do
        primary_key :id
        String :username
        String :password_hash
        String :salt
      end
      hash=OpenSSL::HMAC.hexdigest(OpenSSL::Digest::SHA1.new, "key", "mysalt")
      p "hash is #{hash}"
      p conn[:users].insert(
      :username => "utest",
      :password_hash => hash,
      :salt => "mysalt"
      )
    end
  end

  class TestServer < Sinatra::Base
    set :environment, :production
    enable :sessions


    def die(msg, view)
      @error = msg
      halt(erb(view))
    end

    before do
      refresh_state
    end

    def refresh_state
      @user = logged_in_user
    end


    def logged_in_user
      return unless username = session[:user]
      DB.conn[:users][:username => username]
    end

    #Unsafe Comparison
    def strings_are_equal?(str1, str2)
      _s1=str1.scan(/./)
      _s2=str2.scan(/./)
      # not valid if lengths are different
      return false unless (_s1.length == _s2.length)

      # check each character
      _s1.each_index do |i|
        unless (str1[i] == str2[i])
          #puts "short circuiting @ #{i}- #{str1}!=#{str2}"
          return false 
        else
          sleep(1/10000.0) #this sleep can make comparison time difference obviously
        end
        # puts "matched at index #{i}"
      end

      # yay
      true
    end

    #Constant-time Comparison Algorithm
    def secure_compare(a, b)
      return false unless a.bytesize == b.bytesize
    
      l = a.unpack "C#{a.bytesize}"
    
      res = 0
      b.each_byte { |byte| res |= byte ^ l.shift }
      res == 0
    end

    #select a string comparison function
    def select_cmp_func(str1, str2)
      type = ARGV.first
      if(secure_compare(type.to_s, "safety")) # ensure same compare time
        secure_compare(str1, str2)

      elsif(secure_compare(type.to_s, "danger")) # in order to not influence on timing attack
        strings_are_equal?(str1, str2)

      else
        return false
      end
    end

    post '/timing_attack' do
      username = params[:username]
      p hash_challenge = params[:hash_challenge]
      p user_hash = DB.conn[:users][:username => username][:password_hash]

      if(select_cmp_func(hash_challenge, user_hash))
        "Correct Token"
      else
        "False Token"
      end

    end

    get '/' do
      if @user
        erb :home
      else
        erb :login
      end
    end

    get '/login' do
      redirect '/'
    end

    post '/login' do
      username = params[:username]
      password = params[:password]
      user = DB.conn[:users][:username => username, :password => password]
      unless user
        die('Could not authenticate. Perhaps you meant to register a new' \
        ' account? (See link below.)', :login)
      end

      session[:user] = user[:username]
      redirect '/'
    end
  end
end


def main
  type = ARGV.first
  if(type.to_s == "safety")
    puts "****** Server is using secure comparison algorithm! ******"
  elsif(type.to_s == "danger")
    puts "****** Server is vulnerable now! ******"
  else
    puts "****** Wrong argument! Usage: ruby server.rb [safety/danger] ******"
    return false
  end

  USER_DB::DB.init
  USER_DB::TestServer.run!
end

if $0 == __FILE__
  main
  exit(0)
end
