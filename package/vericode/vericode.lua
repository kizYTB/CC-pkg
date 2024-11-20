--- VeriCode - Easy code signing for ComputerCraft
-- By JackMacWindows
--
-- @module vericode
--
-- Code signing uses encryption and hashes to easily verify a) that the sender of
-- the code is trusted, and b) that the code hasn't been changed mid-transfer.
-- VeriCode applies this concept to Lua code sent over Rednet to add a layer of
-- security to Rednet. Just plainly receiving code from whoever sends it is
-- dangerous, and invites the possibility of getting malware (in fact, I've made
-- a virus that spreads through this method). Adding code signing ensures that
-- any code received is safe and trusted.
--
-- Requires ecc library (pastebin get ZGJGBJdg ecc.lua)

--[[ Basic usage:
1. Generate keypair files with vericode.generateKeypair
2. Copy the .key.pub file (NOT the standard .key file!!!) to each client that
   needs to receive signed code
3. Require the API & load the key (.key on server, .key.pub on clients) - on the
   server, make sure to store the key returned from loadKey as you'll need it to send
4. Call vericode.send to send a Lua script to a client computer
5. Call vericode.receive on the client to listen for code from the server (note
   that it returns after receiving a function, so call it in an infinite loop if
   you want it to always accept code)
Example code:
-- On server:
local vericode = require "vericode"
if not fs.exists("mykey.key") then
    vericode.generateKeypair("mykey.key")
    print("Please copy mykey.key.pub to the client computer.")
    return
end
local key = vericode.loadKey("mykey.key")
vericode.send(otherComputerID, "turtle.forward()", key, "turtleInstructions")
-- On client:
local vericode = require "vericode"
vericode.loadKey("mykey.key.pub")
while true do vericode.receive(true, "turtleInstructions") end
--]]

-- MIT License
--
-- Copyright (c) 2021 JackMacWindows
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in all
-- copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
-- SOFTWARE.

local function minver(version)
    local res
    if _CC_VERSION then res = version <= _CC_VERSION
    elseif not _HOST then res = version <= os.version():gsub("CraftOS ", "")
    elseif _HOST:match("ComputerCraft 1%.1%d+") ~= version:match("1%.1%d+") then
      version = version:gsub("(1%.)([02-9])", "%10%2")
      local host = _HOST:gsub("(ComputerCraft 1%.)([02-9])", "%10%2")
      res = version <= host:match("ComputerCraft ([0-9%.]+)")
    else res = version <= _HOST:match("ComputerCraft ([0-9%.]+)") end
    assert(res, "This program requires ComputerCraft " .. version .. " or later.")
end

minver "1.91.0" -- string.pack, string.unpack
if _VERSION ~= "Lua 5.1" then error("This version of VeriCode only works with Lua 5.1.") end

local expect = require "cc.expect".expect
local ecc = require "ecc"

local vericode = {}
local keyStore = {}

local b64str = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

local function base64encode(str)
    local retval = ""
    for s in str:gmatch "..." do
        local n = s:byte(1) * 65536 + s:byte(2) * 256 + s:byte(3)
        local a, b, c, d = bit32.extract(n, 18, 6), bit32.extract(n, 12, 6), bit32.extract(n, 6, 6), bit32.extract(n, 0, 6)
        retval = retval .. b64str:sub(a+1, a+1) .. b64str:sub(b+1, b+1) .. b64str:sub(c+1, c+1) .. b64str:sub(d+1, d+1)
    end
    if #str % 3 == 1 then
        local n = str:byte(-1)
        local a, b = bit32.rshift(n, 2), bit32.lshift(bit32.band(n, 3), 4)
        retval = retval .. b64str:sub(a+1, a+1) .. b64str:sub(b+1, b+1) .. "=="
    elseif #str % 3 == 2 then
        local n = str:byte(-2) * 256 + str:byte(-1)
        local a, b, c, d = bit32.extract(n, 10, 6), bit32.extract(n, 4, 6), bit32.lshift(bit32.extract(n, 0, 4), 2)
        retval = retval .. b64str:sub(a+1, a+1) .. b64str:sub(b+1, b+1) .. b64str:sub(c+1, c+1) .. "="
    end
    return retval
end

local function base64decode(str)
    local retval = ""
    for s in str:gmatch "...." do
        if s:sub(3, 4) == '==' then
            retval = retval .. string.char(bit32.bor(bit32.lshift(b64str:find(s:sub(1, 1)) - 1, 2), bit32.rshift(b64str:find(s:sub(2, 2)) - 1, 4)))
        elseif s:sub(4, 4) == '=' then
            local n = (b64str:find(s:sub(1, 1))-1) * 4096 + (b64str:find(s:sub(2, 2))-1) * 64 + (b64str:find(s:sub(3, 3))-1)
            retval = retval .. string.char(bit32.extract(n, 10, 8)) .. string.char(bit32.extract(n, 2, 8))
        else
            local n = (b64str:find(s:sub(1, 1))-1) * 262144 + (b64str:find(s:sub(2, 2))-1) * 4096 + (b64str:find(s:sub(3, 3))-1) * 64 + (b64str:find(s:sub(4, 4))-1)
            retval = retval .. string.char(bit32.extract(n, 16, 8)) .. string.char(bit32.extract(n, 8, 8)) .. string.char(bit32.extract(n, 0, 8))
        end
    end
    return retval
end

vericode.base64 = {encode = base64encode, decode = base64decode}
vericode.sha256 = ecc.sha256
vericode.random = ecc.random
vericode.ecc = ecc

--- Generates a keypair for code signing.
-- Outputs a pub/priv keypair at `path`, and a public-only key (for receivers) at `path`.pub.
-- The generated key will be added to the store.
-- @param path string The path to the file to generate.
-- @return string pub The new public key.
-- @return string priv The new private key. (Not required for this API, but might be useful otherwise.)
function vericode.generateKeypair(path)
    expect(1, path, "string")
    local priv, pub = ecc.keypair(ecc.random.random())
    pub, priv = base64encode(string.char(table.unpack(pub))), base64encode(string.char(table.unpack(priv)))
    local file, err = fs.open(path, "w")
    if not file then error("Could not open certificate file: " .. err, 2) end
    file.write(textutils.serialize({
        public = pub,
        private = priv
    }))
    file.close()
    file, err = fs.open(path .. ".pub", "w")
    if not file then error("Could not open public certificate file: " .. err, 2) end
    file.write(textutils.serialize({
        public = pub
    }))
    file.close()
    keyStore[pub] = {
        public = pub,
        private = priv
    }
    return pub, priv
end

--- Loads a key from disk. This can be a full keypair, or only a public key.
-- @param path string The path to the key.
-- @return string key The loaded public key.
function vericode.loadKey(path)
    expect(1, path, "string")
    local file, err = fs.open(path, "r")
    if not file then error("Could not open certificate file: " .. err, 2) end
    local t = textutils.unserialize(file.readAll())
    file.close()
    if type(t) ~= "table" or t.public == nil then error("Invalid certificate file", 2) end
    keyStore[t.public] = t
    return t.public
end

--- Adds a public (and private if provided) key to the key store.
-- @param pub string The public key to add.
-- @param priv string|nil The private key to add, if desired.
function vericode.addKey(pub, priv)
    expect(1, pub, "string")
    expect(2, priv, "string", "nil")
    keyStore[pub] = {
        public = pub,
        private = priv
    }
end

--- Compiles, dumps, and signs a Lua chunk.
-- @param code string The Lua code to compile.
-- @param key string The public or private key to use. The private key associated with this key must exist in the key store.
-- @return string chunk A signed and compiled Lua chunk. This chunk can either be loaded with `load` here, or standard Lua `load`.
function vericode.dump(code, key)
    expect(1, code, "string")
    expect(2, key, "string")
    local pub, priv
    if keyStore[key] then
        if not keyStore[key].private then error("No private key associated with selected public key", 2) end
        pub, priv = key, keyStore[key].private
    else
        for _,v in pairs(keyStore) do
            if v.public == key then
                if not v.private then error("No private key associated with selected public key", 2) end
                pub, priv = key, v.private
                break
            elseif v.private == key then
                pub, priv = v.public, key
                break
            end
        end
    end
    if not pub or not priv then error("Could not find private key", 2) end
    local fn, err = load(code, "=temp")
    if not fn then error("Could not load chunk: " .. err, 2) end
    local dump = string.dump(fn)
    local size_t = dump:byte(9)
    local chunk = dump:sub(19 + size_t)
    local name = "=signed-chunk:" .. pub .. ":" .. base64encode(string.char(table.unpack(ecc.sign(base64decode(priv), chunk)))) .. "\0"
    return dump:sub(1, 12) .. string.pack("T" .. size_t, #name) .. name .. chunk
end

--- Loads and verifies a previously signed code chunk.
-- The public key associated with the chunk must be present in the key store.
-- @param code string The code chunk to load.
-- @param name string|nil The name of the chunk.
-- @param _mode nil Ignored (for compatibility).
-- @param env table|nil The environment to give the chunk.
-- @return function|nil fn The returned function, or nil on error.
-- @return nil|string err If an error occurred, the error message.
function vericode.load(code, name, _mode, env)
    expect(1, code, "string")
    expect(2, name, "string", "nil")
    expect(4, env, "table", "nil")
    if code:sub(1, 5) ~= "\x1bLuaQ" then return nil, "Not a compiled Lua chunk" end
    local size_t = code:byte(9)
    local codename = code:sub(13 + size_t, 12 + size_t + string.unpack("T" .. size_t, code:sub(13, 12 + size_t)))
    local chunk = code:sub(13 + size_t + #codename)
    local key, sig = codename:match "^=signed%-chunk:([A-Za-z0-9+/]+=*):([A-Za-z0-9+/]+=*)\0$"
    if not key or not sig then return nil, "Not signed" end
    if not keyStore[key] then return nil, "Unrecognized key: " .. key end
    if not ecc.verify(base64decode(key), chunk, {base64decode(sig):byte(1, -1)}) then return nil, "Invalid code signature" end
    if name then code = code:sub(1, 12) .. string.pack("T" .. size_t, #name + 1) .. name .. "\0" .. chunk end
    return load(code, name, "b", env)
end

--- Sends a signed code chunk over Rednet.
-- @param recipient number The ID of the recipient.
-- @param code string The code chunk to send.
-- @param key string The key to use to sign the chunk.
-- @param protocol string|nil The protocol to set, if desired.
-- @return boolean ok Whether the message was sent.
function vericode.send(recipient, code, key, protocol)
    expect(1, recipient, "number")
    expect(2, code, "string")
    expect(3, key, "string")
    expect(4, protocol, "string", "nil")
    return rednet.send(recipient, vericode.dump(code, key), protocol)
end

--- Waits to receive a signed code chunk, and either returns the loaded function or the results from calling it.
-- @param run boolean|nil Whether to run the code, or just return the function.
-- @param filter string|nil The name of the protocol to listen for (nil for any).
-- @param timeout number|nil The maximum amount of time to wait.
-- @param name string|nil The name to give the loaded chunk (defaults to "=VeriCode chunk").
-- @param env table|nil The environment to give the function.
-- @return any res Either the loaded function, or the results from the function, or nil if the timeout was passed.
function vericode.receive(run, filter, timeout, name, env)
    expect(1, run, "boolean", "nil")
    expect(2, filter, "string", "nil")
    expect(3, timeout, "number", "nil")
    expect(4, name, "string", "nil")
    expect(5, env, "table", "nil")
    local res = {n = 0}
    local function receive()
        while true do
            local _, message = rednet.receive(filter)
            if type(message) == "string" then
                local fn = vericode.load(message, name or "=VeriCode chunk", nil, env)
                if fn then
                    if run then res = table.pack(fn())
                    else res = {fn, n = 1} end
                    return table.unpack(res, 1, res.n)
                end
            end
        end
    end
    if timeout then
        parallel.waitForAny(receive, function() sleep(timeout) end)
        return table.unpack(res, 1, res.n)
    else return receive() end
end

if ... then vericode.generateKeypair(...) end

return vericode