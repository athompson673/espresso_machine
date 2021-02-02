--[[
http server for static files and websockets based on lua nodemcu firmware (intended only for LAN. Not to be web facing)
(NodeMCU 3.0.0.0 built with Docker provided by frightanic.com) 
https://nodemcu.readthedocs.io/en/release/

call dofile('server.lc') to start server (compile with node.stripdebug(3) for ram savings)
requires c libraries: bit, crypto, encoder, net

exported globals:
	ws_clients: table of "sockets"
		each "socket" is a table with methods:
			onmessage(payload, opcode) --to be overwritten (defaults to global "ws_on_message" which is overridable)
			send(payload, [opcode]) --using opcode 0x01 bu default

	ws_send_all(payload, opcode) --simple helper for calling `for k, v in pairs(ws_clients) do v.send(payload, opcode) end`
--]]
do
	local band = bit.band
	local bor = bit.bor
	local rshift = bit.rshift
	local lshift = bit.lshift
	local char = string.char
	local byte = string.byte
	local sub = string.sub
	local applyMask = crypto.mask
	local toBase64 = encoder.toBase64
	local hash = crypto.hash

	local function ondisconnect(conn)
		conn:on("receive", nil)
		conn:on("disconnection", nil)
		conn:on("sent", nil)
		collectgarbage("collect")
	end

	local function sendfile(filename)
		return function(conn)
			local offset = 0
			local function send()
				local f = file.open(filename, "r")
				if f and f:seek("set", offset) then
					local r = f:read(512)
					f:close()
					if r then
						offset = offset + #r
						conn:send(r, send)
					else
						conn:close()
						ondisconnect(conn)
					end
				end
			end
			send()
		end
	end

	local function decode(chunk)
		if #chunk < 2 then return end
		local second = byte(chunk, 2)
		local len = band(second, 0x7f)
		local offset
		if len == 126 then
			if #chunk < 4 then return end
			len = bor(
				lshift(byte(chunk, 3), 8),
				byte(chunk, 4))
			offset = 4
		elseif len == 127 then
			if #chunk < 10 then return end
			len = bor(
				-- Ignore lengths longer than 32bit
				lshift(byte(chunk, 7), 24),
				lshift(byte(chunk, 8), 16),
				lshift(byte(chunk, 9), 8),
				byte(chunk, 10))
			offset = 10
		else
			offset = 2
		end
		local mask = band(second, 0x80) > 0
		if mask then
			offset = offset + 4
		end
		if #chunk < offset + len then return end

		local first = byte(chunk, 1)
		local payload = sub(chunk, offset + 1, offset + len)
		assert(#payload == len, "Length mismatch")
		if mask then
			payload = applyMask(payload, sub(chunk, offset - 3, offset))
		end
		local extra = sub(chunk, offset + len + 1)
		local opcode = band(first, 0xf)
		return extra, payload, opcode
	end

	local function encode(payload, opcode)
		opcode = opcode or 2
		assert(type(opcode) == "number", "opcode must be number")
		assert(type(payload) == "string", "payload must be string")
		local len = #payload
		local head = char(
			bor(0x80, opcode),
			bor(len < 126 and len or len < 0x10000 and 126 or 127)
		)
		if len >= 0x10000 then
			head = head .. char(
			0,0,0,0, -- 32 bit length is plenty, assume zero for rest
			band(rshift(len, 24), 0xff),
			band(rshift(len, 16), 0xff),
			band(rshift(len, 8), 0xff),
			band(len, 0xff)
		)
		elseif len >= 126 then
			head = head .. char(band(rshift(len, 8), 0xff), band(len, 0xff))
		end
		return head .. payload
	end

	_G.ws_clients = {}

	if _G.ws_on_message == nil then
		_G.ws_on_message = function(payload, opcode)
			print("ws 0x"..tonumber(opcode).." \""..payload.."\"")
		end
	end

	_G.ws_send_all = function(payload, opcode)
		local _, client
		for _, client in pairs(ws_clients) do 
			client.send(payload, opcode) 
		end
	end

	local function handle_ws(conn)
		local buffer = ""
		local socket = {}
		local queue = {}
		local waiting = false
		
		local function onSend()
			if queue[1] then
				local data = table.remove(queue, 1)
				return conn:send(data, onSend)
			end
			waiting = false
		end
		
		function socket.send(payload, opcode)
			opcode = opcode or 1
			local data = encode(payload, opcode)
			if not waiting then
				waiting = true
				conn:send(data, onSend)
			else
				queue[#queue + 1] = data
			end
		end
		
		socket.onmessage = ws_on_message
		
		conn:on("receive", function(_, chunk)
			buffer = buffer .. chunk
			while true do
				local extra, payload, opcode = decode(buffer)
				if not extra then return end
				buffer = extra
				if opcode == 8 then --close
					socket.send(payload, 8) --close echo
					for k, v in pairs(ws_clients) do
						if v == socket then
							table.remove(ws_clients, k)
							ondisconnect(conn)
							return
						end
					end
					conn:close()
					ondisconnect(conn)
				elseif opcode == 9 then --ping
					socket.send(payload, 10) --pong
				elseif socket.onmessage ~= nil then 
					socket.onmessage(payload, opcode)
				end
			end
		end)
		
		conn:on("disconnection", function(conn)
			for k, v in pairs(ws_clients) do
				if v == socket then
					table.remove(ws_clients, k)
					ondisconnect(conn)
					return
				end
			end
		end)
		table.insert(ws_clients, socket)
	end

	local function handle_get(conn, url, headers)
		conn:on('receive', nil) --don't bother with extra data (websocket handler re-sets this as needed)
		if url:lower() == "/ws" then --serve websocket
			if headers["sec-websocket-key"] ~= nil and #ws_clients < 10 then
				conn:send("HTTP/1.1 101 Switching Protocols\r\n" ..
						  "Upgrade: websocket\r\nConnection: Upgrade\r\n" ..
						  "Sec-WebSocket-Accept: " .. 
						  toBase64(hash("sha1", headers["sec-websocket-key"] .. 
						  "258EAFA5-E914-47DA-95CA-C5AB0DC85B11")) .. "\r\n\r\n")
				headers = nil
				handle_ws(conn, ws_c)
			else
				conn:send("HTTP/1.1 400 Bad Request\r\nConnection: Close\r\n\r\n", conn.close)
			end
		else --serve static file
			if url ==  "/" then url = "/index.html" end
			if headers["accept-encoding"] ~= nil and headers["accept-encoding"]:find("gzip") and file.exists("www" .. url .. ".gz") then
				--serve the gzipped file
				conn:send("HTTP/1.1 200 OK\r\n"..
						  "Content-Encoding: gzip\r\n"..
						  "Connection: close\r\n\r\n")
				headers = nil --save memory before sendfile
				conn:on("sent", sendfile("www" .. url .. ".gz"))
			else
				headers = nil --save memory before sendfile
				if file.exists("www" .. url) then
					--serve the file
					conn:send("HTTP/1.1 200 OK\r\n"..
							  "Connection: close\r\n\r\n")
					conn:on("sent", sendfile("www" .. url))
				else
					conn:send("HTTP/1.1 404 Not Found\r\nConnection: Close\r\n\r\n", conn.close)
				end
			end
		end
	end


	local function HTTP_handler(conn)
		local buf = ""
		local method, url
		local headers = {}
		
		conn:on("disconnection", ondisconnect)
		
		conn:on("receive", function(conn, chunk)
			-- merge chunks in buffer
			buf = buf .. chunk

			while #buf > 0 do -- consume buffer line by line
				-- extract line
				local e = buf:find("\r\n", 1, true)
				if not e then break end
				local line = buf:sub(1, e - 1)
				buf = buf:sub(e + 2)
				-- method, url?
				if not method then 
					do
						local _
						-- NB: just version 1.1 assumed
						_, _, method, url = line:find("^([A-Z]+) (.-) HTTP/1.1$")
						if not method == "GET" then
							ondisconnect(conn)
							conn:send("HTTP/1.1 405 Method Not Allowed\r\nConnection: Close\r\n\r\n", conn.close)
						end
					end
				elseif #line > 0 then
					-- parse header
					local _, _, k, v = line:find("^([%w-]+):%s*(.+)")
					-- header seems ok?
					if k then
						k = k:lower()
						headers[k] = v
					end
				else --end of header
					handle_get(conn, url, headers)
				end
			end
		end)
	end
	--start the server:
	local srv = net.createServer(net.TCP, 60) --TCP server with 60 sec timeout
	srv:listen(80, HTTP_handler)
end
