
local function start_ap()
	--switch from sta to ap in case wifi is not set-up
	print('wifi sta not connecting... setting up AP')
	--TODO
end

local function main()
	node.LFS.temp_control()
	node.LFS.server()
	node.LFS.ws_controller()
	--[[
	if file.exists('temp_control.lc') then 
		dofile('temp_control.lc')
	else
		dofile('temp_control.lua')
	end
	if file.exists('server.lc') then 
		dofile('server.lc')
	else
		dofile('server.lua')
	end
	if file.exists('ws_controller.lc') then 
		dofile('ws_controller.lc')
	else
		dofile('ws_controller.lua')
	end
	--]]

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
