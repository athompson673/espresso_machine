
local function start_ap()
	--switch from sta to ap in case wifi is not set-up
	print('wifi sta not connecting... setting up AP')
	--TODO
end

local function main()
	node.LFS.temp_control()
	node.LFS.server()
	node.LFS.ws_controller()
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
