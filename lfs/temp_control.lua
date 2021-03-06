--[[
thermal control routine (all physical controls in this file)
	pin assignments are all at the top of this file, as this deals with the physical controls of the machine
	Pt-RTD zero point calibration
	high / low temp interlock values
	
pid loop calls global: update_clients() every cycle to push data to clients over websockets
	if update_clients == nil (not initialized yet), it is skipped
--]]
do
	--[[move to init.lua for safe startup
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
	--]]
	--local copies of functions
	local floor = math.floor
	local mode, read, write = gpio.mode, gpio.read, gpio.write
	local set_mosi, get_miso, transaction, setup = spi.set_mosi, spi.get_miso, spi.transaction, spi.setup

	--setup bus
	setup(1, spi.MASTER, spi.CPOL_HIGH, spi.CPHA_HIGH, 8, 20)
	--[[move to init.lua for safe startup
	--initialize interfaces
	mode(STEAM_PIN, gpio.INPUT, gpio.PULLUP)
	mode(SSR_PIN, gpio.OUTPUT)
	write(SSR_PIN, 0)
	mode(CS_BREW, gpio.OUTPUT)
	write(CS_BREW, 1)
	mode(CS_STEAM, gpio.OUTPUT)
	write(CS_STEAM, 1)
	--]]
	--initialize chips:
	set_mosi(1, '\128\208')
	write(CS_BREW, 0)
	transaction( 1, 0, 0, 0, 0, 16, 0, 0)
	write(CS_BREW, 1)
	set_mosi(1, '\128\208')
	write(CS_STEAM, 0)
	transaction( 1, 0, 0, 0, 0, 16, 0, 0)
	write(CS_STEAM, 1)

	local function CVD(r0, R)
	--The Callendar Van Dusen Equation for Platinum Based RTD Thermometers
	--excluding case for T < 0C for simplicity
	--Newton's method root finder
		local T, a, b = 0, 3.908300e-3, -5.77500e-7
		local _, r, slope
		for _ = 1,5 do
				r = r0 * (1 + a*T + b*T*T) - R
				slope = r0 * (a + 2*b*T)
				T = T - r/slope
		end
		return T
	end	

	local function read_temps()
		set_mosi(1, '\1')
		write(CS_BREW, 0)
		transaction( 1, 0, 0, 0, 0, 8, 0, 16)
		write(CS_BREW, 1)
		local brew_adc = get_miso(1, 0, 15, 1)
		set_mosi(1, '\1')
		write(CS_STEAM, 0)
		transaction( 1, 0, 0, 0, 0, 8, 0, 16)
		write(CS_STEAM, 1)
		local steam_adc = get_miso(1, 0, 15, 1)
		return CVD(BREW_ZERO, brew_adc), CVD(STEAM_ZERO, steam_adc)
	end

	PID = {} --global

	--local params (todo convert to local vars not PID members)
	PID.interval = 1000 --1 second update rate
	PID.lockout = false --false at startup
	PID.in_manual = false --if currently manual or auto
	PID.last_input = 0 --initialize for deriviative
	PID.integral = 0 --initialize for integral
	--used by outside funcs
	PID.brew_temp, PID.steam_temp = 0,0 --numeric value at startup so never nil
	--will be overridden by config file
	PID.brew_setpoint, PID.steam_setpoint= 0,0 --initialize to cold setpoint, so output doesn't start immediately
	PID.kp,PID.ki, PID.kd = 0,0,0 --pid tuning params
	PID.mode = "auto" --or "manual"
	PID.output = 0 --current output
	
	function PID.compute()
		--switch inputs
		PID.brew_temp, PID.steam_temp = read_temps()
		local input, setpoint
		if read(STEAM_PIN) == 0 then 
			input = PID.steam_temp
			setpoint = PID.steam_setpoint
		else 
			input = PID.brew_temp
			setpoint = PID.brew_setpoint
		end
		
		--over-temp / bad temp lockout:
		if input > HIGH_TEMP_LOCKOUT then
			PID.lockout = true
			print("HIGH_TEMP_LOCKOUT")
		elseif input < LOW_TEMP_LOCKOUT then 
			PID.lockout = true
			print("LOW_TEMP_LOCKOUT")
		end
		if PID.lockout then return end
		
		--auto - manual switching
		if PID.mode == "auto" and PID.in_manual then
			PID.last_input = input --bumpless transfer
			PID.integral = PID.output --bumpless transfer
			PID.in_manual = false
		elseif PID.mode == "manual" then
			PID.in_manual = true
			if PID.output > PID.interval then PID.output = PID.interval --bounds checking
			elseif PID.output < 0 then PID.output = 0 end
			return --let outside function modify PID.output to change manual duty cycle
		end
		
		local err = setpoint - input
		--integral
		PID.integral = PID.integral + (err * PID.ki)
		if PID.integral > PID.interval then PID.integral = PID.interval
		elseif PID.integral < 0 then PID.integral = 0 end
		--deriviative
		local d_input = input - PID.last_input --deriviative on measurement
		PID.last_input = input --save for next deriviative
		--compute output
		PID.output = PID.kp * err + PID.integral - PID.kd * d_input --proportional on error
		if PID.output > PID.interval then PID.output = PID.interval --bounds checking
		elseif PID.output < 0 then PID.output = 0 end
		return 
	end

	--update cycle / pwm SSR output
	PID.finish_cycle = function() end --preallocate circular ref
	function PID.start_cycle()
		PID.compute()
		if PID.output == PID.interval then --100% duty
			write(SSR_PIN, 1)
			local delay = floor(PID.interval + .5)
			tmr.create():alarm(PID.interval, tmr.ALARM_SINGLE, PID.start_cycle)
		elseif PID.output > 0 then --fractional duty
			write(SSR_PIN, 1)
			local delay = floor(PID.output + .5) --round
			tmr.create():alarm(delay, tmr.ALARM_SINGLE, PID.finish_cycle) --delay must be int
		else --0% duty
			write(SSR_PIN, 0)
			local delay = floor(PID.interval + .5)
			tmr.create():alarm(PID.interval, tmr.ALARM_SINGLE, PID.start_cycle)
		end
		if _G.update_clients ~= nil then
			update_clients()
		end
	end

	function PID.finish_cycle()
		write(SSR_PIN, 0)
		local delay = floor(PID.interval - PID.output + .5)
		tmr.create():alarm(PID.interval - PID.output, tmr.ALARM_SINGLE, PID.start_cycle)
	end

	PID.start_cycle()
end
	




