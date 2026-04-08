return function(D)
local M = {}
D.Decompile = M
local C, has = D.Core, D.has

-- ══════════════════════════════════
--  STRATEGY CHAIN
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

local function tryDecompile(obj)
    if not has.decompile then return nil end
    local ok, src = C.timedCall(decompile, D.limits.decompileTimeout, obj)
    if ok and type(src) == "string" and #src > 2 then
        return src, "decompile"
    end
    return nil
end

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
    if count > 0 then
        return table.concat(lines, "\n"), "senv"
    end
    return nil
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
--  PROCESS ONE — mode-adaptive
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
    local mode = D.cfg.mode or "normal"

    -- 1. Always try cache first (instant)
    source, method = tryCache(obj, entry)

    if not source then
        -- 2. Primary: decompile
        source, method = tryDecompile(obj)
    end

    if not source and mode ~= "safe" then
        -- 3. Alternative: closure decompile (skip in safe — risk of crash)
        source, method = tryClosure(obj)
        if source then D.S.stats.aggressive = D.S.stats.aggressive + 1 end
    end

    if not source and mode == "turbo" then
        -- 4. Turbo only: environment dump
        source, method = tryEnvironment(obj)
        if source then D.S.stats.aggressive = D.S.stats.aggressive + 1 end
    end

    if not source then
        -- 5. Last resort: bytecode dump
        source, method = tryBytecode(obj)
        if source then D.S.stats.aggressive = D.S.stats.aggressive + 1 end
    end

    if source then
        -- Cache the result by bytecode hash
        if entry.bcHash and entry.bcHash ~= "EMPTY" and method ~= "cache" then
            D.cache.bytecode[entry.bcHash] = source
        end

        -- Build header
        local header = string.format(
            "-- Script: %s\n-- Path: %s\n-- Method: %s\n-- Source: %s\n\n",
            name, path, method, entry.from or "?"
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