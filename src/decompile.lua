return function(D)
local M = {}
D.Decompile = M
local C, has = D.Core, D.has

-- ══════════════════════════════════
--  DUMPER PRO LOGO
-- ══════════════════════════════════

local LOGO = table.concat({
    "-- ╔══════════════════════════════════════════════════╗",
    "-- ║  ██████╗ ██╗   ██╗███╗   ███╗██████╗ ███████╗  ║",
    "-- ║  ██╔══██╗██║   ██║████╗ ████║██╔══██╗██╔════╝  ║",
    "-- ║  ██║  ██║██║   ██║██╔████╔██║██████╔╝█████╗    ║",
    "-- ║  ██║  ██║██║   ██║██║╚██╔╝██║██╔═══╝ ██╔══╝    ║",
    "-- ║  ██████╔╝╚██████╔╝██║ ╚═╝ ██║██║     ███████╗  ║",
    "-- ║  ╚═════╝  ╚═════╝ ╚═╝     ╚═╝╚═╝     ╚══════╝  ║",
    "-- ║             P R O   v 1 4                        ║",
    "-- ╚══════════════════════════════════════════════════╝",
    "",
}, "\n")

-- ══════════════════════════════════
--  STRATEGY 1: CACHE
-- ══════════════════════════════════

local function tryCache(obj, entry)
    if not entry.bcHash or entry.bcHash == "EMPTY" then return nil end
    local cached = D.cache.bytecode[entry.bcHash]
    if cached then
        D.S.cacheStats.hits = D.S.cacheStats.hits + 1
        return cached, "cache"
    end
    D.S.cacheStats.misses = D.S.cacheStats.misses + 1
    return nil
end

-- ══════════════════════════════════
--  STRATEGY 2: DECOMPILE (primary)
-- ══════════════════════════════════

local function tryDecompile(obj)
    if not has.decompile then return nil end
    local ok, src = C.timedCall(decompile, D.limits.decompileTimeout, obj)
    if ok and type(src) == "string" and #src > 2 then
        return src, "decompile"
    end
    return nil
end

-- ══════════════════════════════════
--  STRATEGY 3: CLOSURE DECOMPILE
-- ══════════════════════════════════

local function tryClosure(obj)
    if not has.getscriptclosure or not has.decompile then return nil end
    local fn
    pcall(function() fn = getscriptclosure(obj) end)
    if not fn then return nil end
    local timeout = math.max(D.limits.decompileTimeout - 2, 3)
    local ok, src = C.timedCall(decompile, timeout, fn)
    if ok and type(src) == "string" and #src > 2 then
        return src, "closure"
    end
    return nil
end

-- ══════════════════════════════════
--  STRATEGY 4: SCRIPT SOURCE (direct)
-- ══════════════════════════════════

local function tryScriptSource(obj)
    local src
    pcall(function()
        local s = obj.Source
        if type(s) == "string" and #s > 2 then src = s end
    end)
    if src then return src, "source_property" end
    return nil
end

-- ══════════════════════════════════
--  STRATEGY 5: CLONE + DECOMPILE
-- ══════════════════════════════════

local function tryCloneDecompile(obj)
    if not has.decompile then return nil end
    local clone
    pcall(function() clone = obj:Clone() end)
    if not clone then return nil end
    local ok, src = C.timedCall(decompile, math.max(D.limits.decompileTimeout - 3, 3), clone)
    pcall(function() clone:Destroy() end)
    clone = nil
    if ok and type(src) == "string" and #src > 2 then
        return src, "clone_decompile"
    end
    return nil
end

-- ══════════════════════════════════
--  STRATEGY 6: GET PROTOS
-- ══════════════════════════════════

local function tryGetProtos(obj)
    if not has.getprotos or not has.getscriptclosure then return nil end
    local fn
    pcall(function() fn = getscriptclosure(obj) end)
    if not fn then return nil end

    local protos
    pcall(function() protos = getprotos(fn) end)
    if not protos or #protos == 0 then return nil end

    local lines = {"-- [Protos extraction — "..#protos.." sub-functions found]", ""}
    for pi, proto in ipairs(protos) do
        if pi > 30 then lines[#lines+1] = "-- ... ("..#protos-30 .." more protos)"; break end
        pcall(function()
            if has.decompile then
                local ok2, src2 = C.timedCall(decompile, 3, proto)
                if ok2 and type(src2) == "string" and #src2 > 2 then
                    lines[#lines+1] = "-- ── Proto #"..pi.." ──"
                    lines[#lines+1] = src2
                    lines[#lines+1] = ""
                end
            end
            -- Extract constants from proto
            if has.getconstants then
                pcall(function()
                    local consts = getconstants(proto)
                    if consts and #consts > 0 then
                        local strs = {}
                        for _, v in ipairs(consts) do
                            if type(v) == "string" and #v > 0 and #v < 80 then
                                strs[#strs+1] = '"'..v:gsub("\n","\\n"):gsub("\r","\\r")..'"'
                            end
                        end
                        if #strs > 0 then
                            lines[#lines+1] = "-- Proto #"..pi.." constants: "..table.concat(strs, ", ")
                        end
                    end
                end)
            end
        end)
    end
    if #lines > 2 then return table.concat(lines, "\n"), "protos" end
    return nil
end

-- ══════════════════════════════════
--  STRATEGY 7: CONSTANTS + UPVALUES RECONSTRUCT
-- ══════════════════════════════════

local function tryConstantsReconstruct(obj)
    if not has.getscriptclosure then return nil end
    local fn
    pcall(function() fn = getscriptclosure(obj) end)
    if not fn then return nil end

    local lines = {"-- [Constants/Upvalues reconstruction — could not decompile]", ""}
    local hasData = false

    -- Constants
    if has.getconstants then
        pcall(function()
            local consts = getconstants(fn)
            if consts and #consts > 0 then
                hasData = true
                lines[#lines+1] = "-- ── Constants ("..#consts..") ──"
                for ci, c in ipairs(consts) do
                    if ci > 200 then lines[#lines+1] = "-- ... ("..#consts-200 .." more)"; break end
                    lines[#lines+1] = string.format("-- [%d] %s = %s", ci, type(c), tostring(c):sub(1,120))
                end
                lines[#lines+1] = ""
            end
        end)
    end

    -- Upvalues
    if has.getupvalues then
        pcall(function()
            local ups = getupvalues(fn)
            if ups then
                local count = 0
                lines[#lines+1] = "-- ── Upvalues ──"
                for k, v in pairs(ups) do
                    count = count + 1
                    if count > 80 then lines[#lines+1] = "-- ... (more upvalues)"; break end
                    hasData = true
                    local vStr = tostring(v):sub(1,150)
                    lines[#lines+1] = string.format("-- [%s] %s = %s", tostring(k), type(v), vStr)
                end
                lines[#lines+1] = ""
            end
        end)
    end

    if hasData then return table.concat(lines, "\n"), "constants_reconstruct" end
    return nil
end

-- ══════════════════════════════════
--  STRATEGY 8: DEBUG.GETINFO STUB
-- ══════════════════════════════════

local function tryDebugInfo(obj)
    if not has["debug.getinfo"] or not has.getscriptclosure then return nil end
    local fn
    pcall(function() fn = getscriptclosure(obj) end)
    if not fn then return nil end

    local info
    pcall(function() info = debug.getinfo(fn) end)
    if not info then return nil end

    local lines = {"-- [Debug info stub — could not decompile]", ""}
    pcall(function()
        if info.name then lines[#lines+1] = "-- Function name: "..tostring(info.name) end
        if info.source then lines[#lines+1] = "-- Source: "..tostring(info.source):sub(1,200) end
        if info.short_src then lines[#lines+1] = "-- Short src: "..tostring(info.short_src):sub(1,200) end
        if info.what then lines[#lines+1] = "-- Type: "..tostring(info.what) end
        if info.numparams or info.nparams then
            lines[#lines+1] = "-- Parameters: "..tostring(info.numparams or info.nparams)
        end
        if info.is_vararg or info.isvararg then lines[#lines+1] = "-- Vararg: yes" end
        if info.linedefined then lines[#lines+1] = "-- Line defined: "..tostring(info.linedefined) end
        if info.lastlinedefined then lines[#lines+1] = "-- Last line: "..tostring(info.lastlinedefined) end
    end)
    lines[#lines+1] = ""

    -- Generate stub function
    local nParams = info.numparams or info.nparams or 0
    local params = {}
    for i = 1, nParams do params[i] = "arg"..i end
    if info.is_vararg or info.isvararg then params[#params+1] = "..." end
    local funcName = info.name or "unknown"
    lines[#lines+1] = string.format("function %s(%s)", funcName, table.concat(params, ", "))
    lines[#lines+1] = "    -- stub: could not decompile body"
    lines[#lines+1] = "end"

    return table.concat(lines, "\n"), "debug_info"
end

-- ══════════════════════════════════
--  STRATEGY 9: REQUIRE FORCE (modules)
-- ══════════════════════════════════

local function tryRequireForce(obj)
    local cn
    pcall(function() cn = obj.ClassName end)
    if cn ~= "ModuleScript" then return nil end

    local result
    local ok = pcall(function()
        result = require(obj)
    end)
    if not ok or result == nil then return nil end

    local lines = {"-- [Module return value — could not decompile source]", ""}
    pcall(function()
        local rType = type(result)
        lines[#lines+1] = "-- Return type: "..rType

        if rType == "table" then
            lines[#lines+1] = "-- Table contents:"
            local count = 0
            for k, v in pairs(result) do
                count = count + 1
                if count > 100 then lines[#lines+1] = "-- ... (truncated)"; break end
                local kStr = tostring(k):sub(1,60)
                local vStr = tostring(v):sub(1,120)
                lines[#lines+1] = string.format("-- [%s] %s (%s) = %s", type(k), kStr, type(v), vStr)
            end
        elseif rType == "function" then
            lines[#lines+1] = "-- Returns a function"
            if has.decompile then
                local ok2, src2 = C.timedCall(decompile, 3, result)
                if ok2 and type(src2) == "string" and #src2 > 2 then
                    lines[#lines+1] = "-- Decompiled return function:"
                    lines[#lines+1] = src2
                end
            end
        else
            lines[#lines+1] = "-- Value: "..tostring(result):sub(1,500)
        end
    end)

    return table.concat(lines, "\n"), "require_force"
end

-- ══════════════════════════════════
--  STRATEGY 10: ENVIRONMENT DUMP
-- ══════════════════════════════════

local function tryEnvironment(obj)
    if not has.getsenv then return nil end
    local ok, env = pcall(getsenv, obj)
    if not ok or not env then return nil end
    local lines = {"-- [Environment dump — could not decompile]"}
    local count = 0
    pcall(function()
        for k, v in pairs(env) do
            count = count + 1
            if count > 100 then break end
            local vStr = tostring(v):sub(1, 200)
            lines[#lines+1] = string.format("-- %s = %s [%s]", tostring(k), vStr, type(v))
        end
    end)
    if count > 0 then return table.concat(lines, "\n"), "senv" end
    return nil
end

-- ══════════════════════════════════
--  STRATEGY 11: BYTECODE DUMP
-- ══════════════════════════════════

local function tryBytecode(obj)
    if not has.getscriptbytecode then return nil end
    local ok, bc = pcall(getscriptbytecode, obj)
    if not ok or not bc or #bc == 0 then return nil end
    local encoded
    if D.base64enc then
        pcall(function() encoded = D.base64enc(bc) end)
    end
    if encoded and #encoded > 0 then
        return string.format(
            "-- [Bytecode: %d bytes — could not decompile]\n-- Base64:\n--[[\n%s\n--]]",
            #bc, encoded
        ), "bytecode_b64"
    end
    return string.format("-- [Bytecode: %d bytes — could not decompile]", #bc), "bytecode_raw"
end

-- ══════════════════════════════════
--  IDENTIFY SCRIPT FROM FUNCTION
-- ══════════════════════════════════

function M.identifyScript(fn)
    if not fn then return "unknown", "unknown", "?" end
    local path, name, class = "unknown", "unknown", "?"
    pcall(function()
        local env = getfenv(fn)
        if not env then return end
        local s = rawget(env, "script")
        if s and typeof(s) == "Instance" then
            pcall(function() path = s:GetFullName() end)
            pcall(function() name = s.Name end)
            pcall(function() class = s.ClassName end)
        end
    end)
    return path, name, class
end

-- ══════════════════════════════════
--  PROCESS ONE — ALL strategies, ALL modes
-- ══════════════════════════════════

function M.processOne(entry)
    if D.S.cancel then return end
    local obj = entry.inst
    if not obj then
        D.S.stats.fail = D.S.stats.fail + 1
        return
    end

    local name, path = "?", "?"
    pcall(function() name = obj.Name end)
    pcall(function() path = obj:GetFullName() end)

    local source, method

    -- Strategy chain: all strategies run in all modes, first success wins
    -- 1. Cache (instant)
    source, method = tryCache(obj, entry)

    -- 2. Direct decompile
    if not source then source, method = tryDecompile(obj) end

    -- 3. Script.Source property
    if not source then source, method = tryScriptSource(obj) end

    -- 4. Closure decompile
    if not source then
        pcall(function() source, method = tryClosure(obj) end)
        if source then D.S.stats.aggressive = D.S.stats.aggressive + 1 end
    end

    -- 5. Clone + decompile
    if not source then
        pcall(function() source, method = tryCloneDecompile(obj) end)
        if source then D.S.stats.aggressive = D.S.stats.aggressive + 1 end
    end

    -- 6. Protos extraction
    if not source then
        pcall(function() source, method = tryGetProtos(obj) end)
        if source then D.S.stats.aggressive = D.S.stats.aggressive + 1 end
    end

    -- 7. Constants/Upvalues reconstruction
    if not source then
        pcall(function() source, method = tryConstantsReconstruct(obj) end)
        if source then D.S.stats.aggressive = D.S.stats.aggressive + 1 end
    end

    -- 8. Debug info stub
    if not source then
        pcall(function() source, method = tryDebugInfo(obj) end)
        if source then D.S.stats.aggressive = D.S.stats.aggressive + 1 end
    end

    -- 9. Require force (modules only)
    if not source then
        pcall(function() source, method = tryRequireForce(obj) end)
        if source then D.S.stats.aggressive = D.S.stats.aggressive + 1 end
    end

    -- 10. Environment dump
    if not source then
        pcall(function() source, method = tryEnvironment(obj) end)
        if source then D.S.stats.aggressive = D.S.stats.aggressive + 1 end
    end

    -- 11. Bytecode dump (last resort)
    if not source then
        source, method = tryBytecode(obj)
        if source then D.S.stats.aggressive = D.S.stats.aggressive + 1 end
    end

    if source then
        -- Cache the result
        if entry.bcHash and entry.bcHash ~= "EMPTY" and method ~= "cache" then
            D.cache.bytecode[entry.bcHash] = source
        end

        -- Build header with logo
        local header = string.format(
            "%s-- Script: %s\n-- Path: %s\n-- Method: %s\n-- Source: %s\n-- Extracted: %s\n\n",
            LOGO, name, path, method, entry.from or "?", os.date("%Y-%m-%d %H:%M:%S")
        )
        local fullSource = header .. source

        -- Save
        if D.S.isSingleFile then
            D.S.singleBuffer[#D.S.singleBuffer+1] = string.format(
                "\n\n-- ═══════════════════════════════════\n-- %s\n-- ═══════════════════════════════════\n%s",
                path, fullSource
            )
        else
            pcall(function()
                local folder, fileName = C.buildFilePath(obj)
                C.writeFile(folder .. "/" .. fileName .. ".lua", fullSource)
            end)
        end

        D.S.stats.ok = D.S.stats.ok + 1
        C.trackMethod(method)
    else
        D.S.stats.fail = D.S.stats.fail + 1
        D.S.fails[#D.S.fails+1] = string.format("[%s] %s (from: %s)", name, path, entry.from or "?")
    end

    -- Push UI update (throttled)
    if (D.S.stats.ok + D.S.stats.fail) % 5 == 0 then
        C.push()
    end
end

end