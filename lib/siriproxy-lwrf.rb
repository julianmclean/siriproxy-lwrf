require 'cora'
require 'siri_objects'
require 'pp'
require 'lightwaverf'

#######
# This is a SiriProxy Plugin For LightWaveRF. It simply intercepts the phrases to
# control LightWaveRF devices and responds with a message about the command that
# is sent to the LightWaveRF gem.
######

class SiriProxy::Plugin::Lwrf < SiriProxy::Plugin


  def initialize(config)
    # get custom configuration options
    if (config.has_key?("debug"))
      @debug = config["debug"] == true
    else
      @debug = false
    end
    @lwrfAuth = nil
    @lwrfAuth = {:email => config["lwrfemail"], :pin => config["lwrfpin"]}
    @debug and (puts "[Info - Lwrf] initialize: Configuration Options: debug => #{@debug}, #{@lwrfAuth.to_s}" )
  end

  #get the user's location and display it in the logs
  #filters are still in their early stages. Their interface may be modified
  filter "SetRequestOrigin", direction: :from_iphone do |object|
    puts "[Info - User Location] lat: #{object["properties"]["latitude"]}, long: #{object["properties"]["longitude"]}"

    #Note about returns from filters:
    # - Return false to stop the object from being forwarded
    # - Return a Hash to substitute or update the object
    # - Return nil (or anything not a Hash or false) to have the object forwarded (along with any
    #    modifications made to it)
  end

  # Command to test plugin
  listen_for /test lightwave/i do
    say "LightWave is in my control using the following config file: #{LightWaveRF.new.get_config_file rescue nil}", spoken: "LightWave is in my control!"
    request_completed
  end
  
  # Commands for Rooms and Devices
  lwrf = LightWaveRF.new
  
  #######################
  # Command regexes start
  #######################
  
  # Fragments
  switch = '(?:(?:turn)|(?:switch))'
  adjust = '(?:(?:dim)|(?:brighten)|(?:set)|(?:adjust)|(?:turn up)|(?:turn down))'
  house = '(?:(?:house)|(?:property)|(?:place)|(?:home))'
  all = '(?:(all(?: the)? lights)|(?:everything))'
  percent = '([1-9][0-9]?)(?:%| percent)?'
  level = '(\w+)(?: (?:level|setting|brightness)?)?'
  set = '(?:(?:set)|(?:activate)|(?:enable)|(?:change))'
  mood = '(?:(?:mood)|(?:mode)|(?:setting))'
  run = '(?:(?:run)|(?:launch)|(?:activate))'
  update = '(?:(?:update)|(?:download))'
  data = '(?:(?:config)|(?:setup)|(?:data)|(?:device list))'
  roomWord = '(?: (room|area|space))?'
  deviceWord = '(?: (light|lamp))?'
  
  # Commands to update config file
  listen_for (/#{update}(?: (?:my)|(?:the)) lightwave #{data}/i) do 
    unless @lwrfAuth.nil?
      say "Updating the LightwaveRF configuration for #{@lwrfAuth[:email]} from the server"
      LightWaveRF.new.update_config @lwrfAuth[:email], @lwrfAuth[:pin], @debug rescue nil
    else
      say "I'm sorry, I don't seem to have access to the server. Have you updated the config file correctly?"
    end
    request_completed
  end
    
  # Commands to control all the devices in the house
  listen_for (/#{switch} off #{all}(?: the) lights(?: (?:in)|(?:at))(?: the)? #{house}/i) { | | send_lwrf_command('mood','all','alloff') }
  
  # Commands to control all the devices in a single room
  listen_for (/#{switch} (on|off) #{all} in(?: the)? (\w+)#{roomWord}/i) { | action, roomName, roomWord | send_lwrf_command('mood',roomName, roomWord,'all'+action) }
  listen_for (/#{adjust} all(?: the)? lights in(?: the)? (\w+)#{roomWord} to (?:a )?#{percent}/i) { |roomName, action, roomWord| send_lwrf_command('mood',roomName, roomWord,'all' + action) }
  listen_for (/#{adjust} all(?: the)? lights in(?: the)? (\w+)#{roomWord} to (?:a )?#{level}/i) { |roomName, action, roomWord| send_lwrf_command('mood',roomName, roomWord,'all' + action) }
  
  # Commands to control a single devices in a single room
  listen_for (/#{switch} (on|off)(?: the)? (\w+)#{deviceWord} in(?: the)? (#{room["name"]})#{roomWord}/i) { | action, deviceName, roomName, roomWord | send_lwrf_command('device',roomName,roomWord,deviceName,deviceWord,action) }
  listen_for (/#{switch} (on|off)(?: the)? (#{room["name"]})#{roomWord} (\w+)#{deviceWord}/i) { | action, roomName, deviceName, roomWord | send_lwrf_command('device',roomName,roomWord,deviceName,deviceWord,action) }
  listen_for (/#{adjust}(?: the)? (\w+)#{deviceWord} in(?: the)? (#{room["name"]})#{roomWord} to (?:a )?#{percent}/i) { |deviceName, roomName, action, roomWord| send_lwrf_command('device',roomName,roomWord,deviceName,deviceWord,action) }
  listen_for (/#{adjust}(?: the)? (\w+)#{deviceWord} in(?: the)? (#{room["name"]})#{roomWord} to (?:a )?#{level}/i) { |deviceName, roomName, action, roomWord| send_lwrf_command('device',roomName,roomWord,deviceName,deviceWord,action) }
  listen_for (/#{adjust}(?: the)? (#{room["name"]})#{roomWord} (\w+)#{deviceWord} to (?:a )#{percent}/i) { |roomName, deviceName, action, roomWord| send_lwrf_command('device',roomName,roomWord,deviceName,deviceWord,action) }
  listen_for (/#{adjust}(?: the)? (#{room["name"]})#{roomWord} (\w+)#{deviceWord} to (?:a )?#{level}/i) { |roomName, deviceName, action, roomWord| send_lwrf_command('device',roomName,roomWord,deviceName,deviceWord,action) }

  # Commands to set a mood in a single room
  listen_for (/#{set}(?: the)?(?: lighting)? mood(?: called)? (#{moodName}) in(?: the)? (#{room["name"]})#{roomWord}/i) { |moodName, roomName, roomWord| send_lwrf_command('mood',roomName, roomWord,moodName) }
  listen_for (/#{set}(?: the)? (#{moodName})(?: lighting)?  mood in(?: the)? (#{room["name"]})#{roomWord}/i) { |moodName, roomName, roomWord| send_lwrf_command('mood',roomName, roomWord,moodName) }

  # Commands to run a sequence
  listen_for (/#{run}(?: the)? sequence(?: called)? (#{sequenceName})/i) { |sequenceName| send_lwrf_command('sequence',sequenceName) }    
  listen_for (/#{run}(?: the)? (#{sequenceName}) sequence/i) { |sequenceName| send_lwrf_command('sequence',sequenceName) }
  
  # Custom commands
  if lwrf.get_config.has_key?('custom_phrases')
    lwrf.get_config['custom_phrases'].each do | phrase |
      if phrase.has_key?('inputs')
        phrase["inputs"].each do | input |    
          # Commands for custom phrases
          listen_for (/#{input}/i) { | | run_custom_command(phrase) }
        end
      end
    end
  end
  
  #######################
  # Command regexes end
  #######################
  
  ## Commands to turn on/off all the devices in a room
  #listen_for (/(?:(?:turn)|(?:switch)) off all(?: the) lights in the(?: (?:house)|(?:property)|(?:place)|(?:home))/i) { | | send_lwrf_command('mood','all','alloff') }
  #
  #lwrf.get_config['room'].each do | room |
  #  
  #  # Commands to turn on/off all the devices in a room
  #  listen_for (/(?:(?:turn)|(?:switch)) off all(?: the) lights in the (#{room["name"]})(?: room)/i) { |roomName| send_lwrf_command('mood',roomName,'alloff') }
  #  listen_for (/(?:(?:turn)|(?:switch)) on all(?: the) lights in the (#{room["name"]})(?: room)/i) { |roomName| send_lwrf_command('mood',roomName,'allon') }
  #
  #  # Commands to dim all the devices in a room
  #  listen_for (/(?:(?:dim)|(?:set)|(?:turn up)|(?:turn down)|(?:set level on)|(?:set the level on)) all(?: the) lights in the (#{room["name"]})(?: room) to ([1-9][0-9]?)(?:%| percent)?/i) { |roomName, action| send_lwrf_command('mood',roomName,'all' + action) }
  #  listen_for (/(?:(?:dim)|(?:set)|(?:turn up)|(?:turn down)|(?:set level on)|(?:set the level on)) all(?: the) lights in the (#{room["name"]})(?: room) to (?: a)(low|mid|high|full)(:? level)/i) { |roomName, action| send_lwrf_command('mood',roomName,'all' + action) }
  #
  #  # Devices
  #  room["device"].each do | deviceName |    
  #    # Commands to turn on/off a device in a room
  #    listen_for (/turn (on|off) the (#{deviceName}) in the (#{room["name"]})(?: room)/i) { |action, deviceName, roomName| send_lwrf_command('device',roomName,deviceName,action) }
  #    listen_for (/turn (on|off) the (#{room["name"]})(?: room) (#{deviceName})/i)        { |action, roomName, deviceName| send_lwrf_command('device',roomName,deviceName,action) }
  #    listen_for (/turn the (#{deviceName}) in the (#{room["name"]})(?: room) (on|off)/i) { |deviceName, roomName, action| send_lwrf_command('device',roomName,deviceName,action) }
  #    listen_for (/turn the (#{room["name"]})(?: room) (#{deviceName}) (on|off)/i)        { |roomName, deviceName, action| send_lwrf_command('device',roomName,deviceName,action) }
  #
  #    # Commands to dim a devices in a room
  #    listen_for (/(?:(?:dim)|(?:set)|(?:turn up)|(?:turn down)|(?:set level on)|(?:set the level on)) the (#{deviceName}) in the (#{room["name"]})(?: room) to ([1-9][0-9]?)(?:%| percent)?/i) { |deviceName, roomName, action| send_lwrf_command('device',roomName,deviceName,action) }
  #    listen_for (/(?:(?:dim)|(?:set)|(?:turn up)|(?:turn down)|(?:set level on)|(?:set the level on)) the (#{deviceName}) in the (#{room["name"]})(?: room) to (?: a)(low|mid|high|full)(:? level)/i) { |deviceName, roomName, action| send_lwrf_command('device',roomName,deviceName,action) }
  #    listen_for (/(?:(?:dim)|(?:set)|(?:turn up)|(?:turn down)|(?:set level on)|(?:set the level on)) the (#{room["name"]})(?: room) (#{deviceName}) to ([1-9][0-9]?)(?:%| percent)?/i)        { |roomName, deviceName, action| send_lwrf_command('device',roomName,deviceName,action) }
  #    listen_for (/(?:(?:dim)|(?:set)|(?:turn up)|(?:turn down)|(?:set level on)|(?:set the level on)) the (#{room["name"]})(?: room) (#{deviceName}) to (?: a)(low|mid|high|full)(:? level)/i)        { |roomName, deviceName, action| send_lwrf_command('device',roomName,deviceName,action) }
  #
  #  end
  #  
  #  # Moods
  #  if room.has_key?('mood')
  #    room['mood'].each do | moodName |    
  #      # Commands to set a mood in a room
  #      listen_for (/mood (#{room["name"]}) (#{moodName})/i) { |roomName, moodName| send_lwrf_command('mood',roomName,moodName) }
  #      listen_for (/(?:(?:set)|(?:activate))(?: the) mood(?: called) (#{moodName}) in the (#{room["name"]})(?: room)/i) { |moodName, roomName| send_lwrf_command('mood',roomName,moodName) }
  #      listen_for (/(?:(?:set)|(?:activate))(?: the) (#{moodName}) mood in the (#{room["name"]})(?: room)/i) { |moodName, roomName| send_lwrf_command('mood',roomName,moodName) }
  #    end
  #  end
  #end
  #
  ## Sequences
  #lwrf.get_config['sequence'].each do | config, sequenceName |
  #  # Commands to run a sequence
  #  listen_for (/sequence (#{sequenceName})/i) { |sequenceName| send_lwrf_command('sequence',sequenceName) }    
  #  listen_for (/(?:(?:run)|(?:launch)|(?:activate))(?: the) sequence(?: called) (#{sequenceName})/i) { |sequenceName| send_lwrf_command('sequence',sequenceName) }    
  #  listen_for (/(?:(?:run)|(?:launch)|(?:activate))(?: the)(#{sequenceName}) sequence/i) { |sequenceName| send_lwrf_command('sequence',sequenceName) }    
  #end
    
  def run_custom_command (phrase)
    begin
      if phrase.has_key?('action')
        case phrase['action'][0]
        when 'mood'
          send_lwrf_command('mood',phrase['action'][1],nil,phrase['action'][2])
        when 'sequence'
          send_lwrf_command('sequence',phrase['action'][1])
        else
          send_lwrf_command('device',phrase['action'][0],nil,phrase['action'][1],nil,phrase['action'][2].to_s)          
        end
      else
        say "No action has been configured for this phrase. Please check your config file."  
      end
    rescue Exception
      pp $!
      say "Sorry, I encountered an error. Please check the action configured for this phrase."
      @debug and (puts "[Info - Lwrf] send_lwrf_command: Error => #{$!}" )
    end
  end  

  def send_lwrf_command (type, roomName, roomWord = nil, deviceName = nil, deviceWord = nil, action = nil)
    begin
      @debug and (puts "[Info - Lwrf] send_lwrf_command: Starting with arguments: type => #{type}, roomName => #{roomName}, deviceName => #{deviceName}, action => #{action} ")
      # initialise LightWaveRF Gem
      @debug and (puts "[Info - Lwrf] send_lwrf_command: Instantiating LightWaveRF Gem")
      lwrf = LightWaveRF.new rescue nil
      @debug and (puts "[Info - Lwrf] send_lwrf_command: lwrf => #{lwrf}" )
      # Get raw config
      lwrfConfig = lwrf.get_config rescue nil
      # ...and also the processed version so we can access aliases, etc.
      lwrfRooms = lwrf.get_rooms lwrfConfig
      @debug and (puts "[Info - Lwrf] send_lwrf_command: lwrfConfig => #{lwrfConfig}" )
      
      roomName = roomName.downcase
      deviceName = deviceName.downcase
      
      #Create phrases to refer to the room/device using the user's natural language
      roomPhrase = roomWord.nil? ? roomName : (roomName + " " + roomWord)
      devicePhrase = deviceWord.nil? ? deviceName : (deviceName + " " + deviceWord)
      
      case type
      # if a mood...
      when 'mood'
        if roomName == 'all'
          if deviceName == 'alloff'
            say "Switching off all the lights in the house."
            lwrf.mood 'all', 'alloff', @debug rescue nil
            @debug and (puts "[Info - Lwrf] send_lwrf_command: Command sent to LightWaveRF Gem" )
          else
            say "I'm only able to switch off all the lights in the house."            
          end          
        elsif deviceName[0,3] == 'all'
          if lwrfRooms.has_key?("room")
            if lwrfRooms["room"].has_key?(roomName)
              state = deviceName[3..-1]
              case state
                when 'off'
                  say "Switching off all the lights in the #{roomPhrase}"
                when 'on'
                  say "Switching on all the lights in the #{roomPhrase}"
                when 'low'
                  say "Setting all the lights in the #{roomPhrase} to a low level."
                when 'mid'
                  say "Setting all the lights in the #{roomPhrase} to a mid level."
                when 'high'
                  say "Setting all the lights in the #{roomPhrase} to a high level."
                when 'full'
                  say "Setting all the lights in the #{roomPhrase} to full."
                # TODO: need to fix this as state is text, not a number
                when 1..100
                  value = 'FdP' + ( state * 0.32 ).round.to_s
                  say "Setting all the lights in the #{roomPhrase} to #{value} percent."
                else
                  say "Setting all the lights in the #{roomPhrase} to state: #{state}."
              end
              lwrf.mood roomName, deviceName, @debug rescue nil
              @debug and (puts "[Info - Lwrf] send_lwrf_command: Command sent to LightWaveRF Gem" )
            else
              say "I'm sorry, I can't find a room called '#{roomName}'."
            end
          else
            say "I'm sorry, I can't find any rooms in your config file."
          end
        else
          if lwrfRooms.has_key?("room")
            if lwrfRooms["room"].has_key?(roomName)
              if lwrfRooms["room"][roomName].has_key?("mood")
                if lwrfRooms["room"][roomName]["mood"].has_key?(deviceName)
                  say "Setting mood #{deviceName} in the #{roomPhrase}."
                  lwrf.mood roomName, deviceName, @debug rescue nil
                  @debug and (puts "[Info - Lwrf] send_lwrf_command: Command sent to LightWaveRF Gem" )
                else
                  say "I'm sorry, I can't find a mood called '#{deviceName}' in the room called '#{roomName}'."
                end
              else
                say "I'm sorry, the room called '#{roomName}' does not have any configured moods."
              end
            else
              say "I'm sorry, I can't find a room called '#{roomName}'."
            end
          else    
            say "I'm sorry, I can't find any rooms in your config file."
          end
        end
        
      # if a sequence...
      when 'sequence'
        if lwrfConfig.has_key?("sequence")
          if lwrfConfig["sequence"].has_key?(roomName)
              say "Running sequence #{roomName}."
              lwrf.sequence roomName, @debug rescue nil
              @debug and (puts "[Info - Lwrf] send_lwrf_command: Command sent to LightWaveRF Gem" )
          else
            say "I'm sorry, I can't find a sequence called '#{roomName}'."
          end
        else    
          say "I'm sorry, I can't find any sequences in your config file."
        end

      # else a device
      else
        # Validate Inputs - NB: siri passes lowercase values, but lwrf.send is case sensitive!
        if lwrfRooms.has_key?("room")
          if lwrfRooms["room"].has_key?(roomName)
            if lwrfRooms["room"][roomName].has_key?("device")              
              if lwrfRooms["room"][roomName]["device"].has_key?(deviceName)
                say "Turning #{action} the #{roomPhrase} in the #{roomPhrase}."
                lwrf.send roomName, deviceName, action, @debug rescue nil
                @debug and (puts "[Info - Lwrf] send_lwrf_command: Command sent to LightWaveRF Gem" )
              else
                say "I'm sorry, I can't find a device called '#{deviceName}' in the room called '#{roomName}'."
              end
            else
              say "I'm sorry, the room called '#{roomName}' does not have any configured devices."
            end            
          else
            say "I'm sorry, I can't find a room called '#{roomName}'."
          end
        else    
          say "I'm sorry, I can't find a room called '#{roomName}'."
        end
      end

    rescue Exception
      pp $!
      say "Sorry, I encountered an error"
      @debug and (puts "[Info - Lwrf] send_lwrf_command: Error => #{$!}" )
    end
    @debug and (puts "[Info - Lwrf] send_lwrf_command: Request Completed" )
    request_completed
  end

end
