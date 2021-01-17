--constants
--pin assignments:
local CS_BREW  = 3
local CS_STEAM = 4
local STEAM_PIN = 1
local SSR_PIN = 2
--calibration: 
local BREW_ZERO = 7620.5 --adc reading at 0C
local STEAM_ZERO = 7620.5
--safety:
local HIGH_TEMP_LOCKOUT = 170 --temp above this value is an error, or thermal runaway
local LOW_TEMP_LOCKOUT = 10 --temp below this value is an error (or a broken furnace)
--initialize interfaces:
gpio.mode(STEAM_PIN, gpio.INPUT, gpio.PULLUP)
gpio.mode(SSR_PIN, gpio.OUTPUT)
gpio.write(SSR_PIN, 0)
gpio.mode(CS_BREW, gpio.OUTPUT)
gpio.write(CS_BREW, 1)
gpio.mode(CS_STEAM, gpio.OUTPUT)
gpio.write(CS_STEAM, 1)



local function start_ap()
	--switch from sta to ap in case wifi is not set-up
	print('wifi sta not connecting... setting up AP')
	--TODO
end

local function main()
	node.LFS.temp_control() --start PID routine
	node.LFS.server() --start HTTP / WS server
	node.LFS.ws_controller() --initialize server-side WS responder
	--read config file into PID controller
	local f = file.open('config', 'r')
	if f ~= nil then
		local cfg = f:readline()
		while cfg ~= nil do
			--initialize config the same way we set values from websockets
			ws_on_message(cfg, 1) 
			cfg = f:readline()
		end
		f:close()
	end
	local poll_wifi_retries = 0
	local function poll_wifi(timer)
		poll_wifi_retries = poll_wifi_retries + 1
		if wifi.getmode() ~= wifi.STATION then
			wifi.setmode(wifi.STATION)
		end
		if wifi.sta.status() == wifi.STA_GOTIP then
			local ip, nm, gw = wifi.sta.getip()
			print('wifi sta connected with IP: '..ip)
		else
			if poll_wifi_retries > 10 then
				start_ap()
			else
				tmr.create():alarm(1000, tmr.ALARM_SINGLE, poll_wifi)
			end
		end
	end
	
	poll_wifi()
end

startup = tmr.create()
startup:alarm(2000, tmr.ALARM_SINGLE, main)

print('station mac address for setting static ip: '..wifi.sta.getmac())
print('starting in 2 sec call startup:unregister() to stop')
