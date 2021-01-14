do	
	local funcs = {}
	funcs.ssid = function(value)
		wifi.sta.config({ssid=value})
	end
	funcs.pwd = function(value)
		wifi.sta.config({pwd=value})
	end
	funcs.brew_setpoint = function(value)
		PID.brew_setpoint = tonumber(value) or PID.brew_setpoint
	end
	funcs.steam_setpoint = function(value)
		PID.steam_setpoint = tonumber(value) or PID.steam_setpoint
	end
	funcs.kp = function(value)
		PID.kp = tonumber(value) or PID.kp
	end
	funcs.ki = function(value)
		PID.ki = tonumber(value) or PID.ki
	end
	funcs.kd = function(value)
		PID.kd = tonumber(value) or PID.kd
	end
	funcs.mode = function(value)
		if value == 'auto' then PID.mode = 'auto'
		elseif value == 'manual' then PID.mode = 'manual'
		end
	end
	funcs.output = function(value)
		if PID.mode == 'manual' then
			PID.output = tonumber(value) or PID.output
		end
	end
	funcs.get_config = function(value)
		local msg = 'brew_setpoint:'..tostring(PID.brew_setpoint)..
		'\nsteam_setpoint:'..tostring(PID.steam_setpoint)..
		'\nkp:'..tostring(PID.kp)..
		'\nki:'..tostring(PID.ki)..
		'\nkd:'..tostring(PID.kd)..
		'\nmode:'..PID.mode..
		'\noutput:'..tostring(PID.output)
		ws_send_all(msg, 1)
	end
	funcs.save_config = function(value)
		local f = file.open('config', 'w')
		if f ~= nil then
			local msg = 'brew_setpoint:'..tostring(PID.brew_setpoint)..
			'\nsteam_setpoint:'..tostring(PID.steam_setpoint)..
			'\nkp:'..tostring(PID.kp)..
			'\nki:'..tostring(PID.ki)..
			'\nkd:'..tostring(PID.kd)..
			'\nmode:'..PID.mode..
			'\noutput:'..tostring(PID.output)
			f.write(msg)
			f:close()
		end
	end

	function ws_on_message(payload, opcode) --overwrite default ws_on_message
		if opcode ~= 1 then return end --only handle text opcode
		--for each line
			--split on first ":" into key:value
			if funcs[key] ~= nil then
				funcs[key](value)
			end
	end

	function update_clients() --called every PID interval
		local msg = 'brew_temp:'..tostring(PID.brew_temp)..
		'\nsteam_temp:'..tostring(PID.steam_temp)..
		'\noutput:'..tostring(PID.output)
		ws_send_all(msg, 1)
	end
end