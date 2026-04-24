return function(D)
local M = {}
D.Decompile = M
local C, has = D.Core, D.has

local LOGO = table.concat({
    "-- ╔══════════════════════════════════════════════════╗",
    "-- ║  ██████╗ ██╗   ██╗███╗   ███╗██████╗ ███████╗  ║",
    "-- ║  ██╔══██╗██║   ██║████╗ ████║██╔══██╗██╔════╝  ║",
    "-- ║  ██║  ██║██║   ██║██╔████╔██║██████╔╝█████╗    ║",
    "-- ║  ██║  ██║██║   ██║██║╚██╔╝██║██╔═══╝ ██╔══╝    ║",
    "-- ║  ██████╔╝╚██████╔╝██║ ╚═╝ ██║██║     ███████╗  ║",
    "-- ║  ╚═════╝  ╚═════╝ ╚═╝     ╚═╝╚═╝     ╚══════╝  ║",
    "-- ║             P R O   v 1 5                        ║",
    "-- ╚══════════════════════════════════════════════════╝",
    "",
}, "\n")

-- ══ 1: CACHE ══
local function tryCache(obj, entry)
    if not entry.bcHash or entry.bcHash == "EMPTY" then return nil end
    local cached = D.cache.bytecode[entry.bcHash]
    if cached then D.S.cacheStats.hits = D.S.cacheStats.hits + 1; return cached, "cache" end
    D.S.cacheStats.misses = D.S.cacheStats.misses + 1
    return nil
end

-- ══ 2: DECOMPILE ══
local function tryDecompile(obj)
    if not has.decompile then return nil end
    local ok, src = C.timedCall(decompile, D.limits.decompileTimeout, obj)
    if ok and type(src) == "string" and #src > 2 then return src, "decompile" end
    return nil
end

-- ══ 3: CLOSURE DECOMPILE ══
local function tryClosure(obj)
    if not has.getscriptclosure or not has.decompile then return nil end
    local fn; pcall(function() fn = getscriptclosure(obj) end)
    if not fn then return nil end
    local ok, src = C.timedCall(decompile, math.max(D.limits.decompileTimeout - 2, 3), fn)
    if ok and type(src) == "string" and #src > 2 then return src, "closure" end
    return nil
end

-- ══ 4: SCRIPT SOURCE ══
local function tryScriptSource(obj)
    local src; pcall(function() local s = obj.Source; if type(s) == "string" and #s > 2 then src = s end end)
    if src then return src, "source_property" end
    return nil
end

-- ══ 5: CLONE + DECOMPILE ══
local function tryCloneDecompile(obj)
    if not has.decompile then return nil end
    local clone; pcall(function() clone = obj:Clone() end)
    if not clone then return nil end
    local ok, src = C.timedCall(decompile, math.max(D.limits.decompileTimeout - 3, 3), clone)
    pcall(function() clone:Destroy() end)
    if ok and type(src) == "string" and #src > 2 then return src, "clone_decompile" end
    return nil
end

-- ══ 6: GET PROTOS (unlimited) ══
local function tryGetProtos(obj)
    if not has.getprotos or not has.getscriptclosure then return nil end
    local fn; pcall(function() fn = getscriptclosure(obj) end)
    if not fn then return nil end
    local protos; pcall(function() protos = getprotos(fn) end)
    if not protos or #protos == 0 then return nil end

    local lines = {"-- [Protos extraction — "..#protos.." sub-functions]", ""}
    local function decompProtos(parentFn, depth, prefix)
        if depth > 3 then return end
        local ps; pcall(function() ps = getprotos(parentFn) end)
        if not ps then return end
        for pi, proto in ipairs(ps) do
            pcall(function()
                if has.decompile then
                    local ok2, src2 = C.timedCall(decompile, 3, proto)
                    if ok2 and type(src2) == "string" and #src2 > 2 then
                        lines[#lines+1] = "-- ── "..prefix.."Proto #"..pi.." ──"
                        lines[#lines+1] = src2; lines[#lines+1] = ""
                    end
                end
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
                            if #strs > 0 then lines[#lines+1] = "-- "..prefix.."Proto #"..pi.." constants: "..table.concat(strs, ", ") end
                        end
                    end)
                end
                decompProtos(proto, depth + 1, prefix.."  ")
            end)
        end
    end
    decompProtos(fn, 0, "")
    if #lines > 2 then return table.concat(lines, "\n"), "protos" end
    return nil
end

-- ══ 7: CONSTANTS + UPVALUES ══
local function tryConstantsReconstruct(obj)
    if not has.getscriptclosure then return nil end
    local fn; pcall(function() fn = getscriptclosure(obj) end)
    if not fn then return nil end
    local lines = {"-- [Constants/Upvalues reconstruction]", ""}
    local hasData = false
    if has.getconstants then
        pcall(function()
            local consts = getconstants(fn)
            if consts and #consts > 0 then
                hasData = true
                lines[#lines+1] = "-- ── Constants ("..#consts..") ──"
                for ci, c in ipairs(consts) do
                    if ci > 300 then lines[#lines+1] = "-- ... ("..(#consts-300).." more)"; break end
                    local repr = type(c) == "string" and ('"'..c:sub(1,100):gsub("\n","\\n")..'"') or tostring(c):sub(1,120)
                    lines[#lines+1] = string.format("-- [%d] <%s> %s", ci, type(c), repr)
                end
                lines[#lines+1] = ""
            end
        end)
    end
    if has.getupvalues then
        pcall(function()
            local ups = getupvalues(fn)
            if ups then
                local count = 0
                lines[#lines+1] = "-- ── Upvalues ──"
                for k, v in pairs(ups) do
                    count = count + 1
                    if count > 80 then lines[#lines+1] = "-- ... (more)"; break end
                    hasData = true
                    lines[#lines+1] = string.format("-- [%s] <%s> %s", tostring(k), type(v), tostring(v):sub(1,150))
                end
                lines[#lines+1] = ""
            end
        end)
    end
    if hasData then return table.concat(lines, "\n"), "constants_reconstruct" end
    return nil
end

-- ══ 8: DEBUG.GETINFO STUB ══
local function tryDebugInfo(obj)
    if not has["debug.getinfo"] or not has.getscriptclosure then return nil end
    local fn; pcall(function() fn = getscriptclosure(obj) end)
    if not fn then return nil end
    local info; pcall(function() info = debug.getinfo(fn) end)
    if not info then return nil end
    local lines = {"-- [Debug info stub]", ""}
    pcall(function()
        if info.name then lines[#lines+1] = "-- Function: "..tostring(info.name) end
        if info.source then lines[#lines+1] = "-- Source: "..tostring(info.source):sub(1,200) end
        if info.short_src then lines[#lines+1] = "-- Short src: "..tostring(info.short_src):sub(1,200) end
        if info.what then lines[#lines+1] = "-- Type: "..tostring(info.what) end
        if info.numparams or info.nparams then lines[#lines+1] = "-- Params: "..tostring(info.numparams or info.nparams) end
        if info.is_vararg or info.isvararg then lines[#lines+1] = "-- Vararg: yes" end
        if info.linedefined then lines[#lines+1] = "-- Line: "..tostring(info.linedefined).."-"..tostring(info.lastlinedefined or "?") end
    end)
    lines[#lines+1] = ""
    local nP = info.numparams or info.nparams or 0
    local params = {}; for i = 1, nP do params[i] = "arg"..i end
    if info.is_vararg or info.isvararg then params[#params+1] = "..." end
    lines[#lines+1] = string.format("function %s(%s)", info.name or "unknown", table.concat(params, ", "))
    lines[#lines+1] = "    -- stub: could not decompile body"
    lines[#lines+1] = "end"
    return table.concat(lines, "\n"), "debug_info"
end

-- ══ 9: REQUIRE FORCE (recursive) ══
local function tryRequireForce(obj)
    local cn; pcall(function() cn = obj.ClassName end)
    if cn ~= "ModuleScript" then return nil end
    local result; local ok = pcall(function() result = require(obj) end)
    if not ok or result == nil then return nil end
    local lines = {"-- [Module return value — recursive dump]", ""}
    local function dumpVal(val, depth, prefix)
        if depth > 3 then return end
        local rType = type(val)
        if rType == "table" then
            lines[#lines+1] = prefix.."-- Table:"
            local count = 0
            for k, v in pairs(val) do
                count = count + 1; if count > 60 then lines[#lines+1] = prefix.."-- ... (truncated)"; break end
                local kS = tostring(k):sub(1,50)
                if type(v) == "table" and depth < 3 then
                    lines[#lines+1] = string.format("%s-- [%s] <table>:", prefix, kS)
                    dumpVal(v, depth + 1, prefix.."  ")
                elseif type(v) == "function" and has.decompile then
                    lines[#lines+1] = string.format("%s-- [%s] <function>", prefix, kS)
                    pcall(function()
                        local ok2, src2 = C.timedCall(decompile, 3, v)
                        if ok2 and type(src2) == "string" and #src2 > 2 then
                            lines[#lines+1] = prefix.."-- Decompiled:"; lines[#lines+1] = src2
                        end
                    end)
                else
                    lines[#lines+1] = string.format("%s-- [%s] <%s> = %s", prefix, kS, type(v), tostring(v):sub(1,100))
                end
            end
        elseif rType == "function" and has.decompile then
            lines[#lines+1] = prefix.."-- Returns function"
            pcall(function()
                local ok2, src2 = C.timedCall(decompile, 3, val)
                if ok2 and type(src2) == "string" and #src2 > 2 then lines[#lines+1] = src2 end
            end)
        else
            lines[#lines+1] = prefix.."-- Value: "..tostring(val):sub(1,500)
        end
    end
    pcall(function() dumpVal(result, 0, "") end)
    return table.concat(lines, "\n"), "require_force"
end

-- ══ 10: ENVIRONMENT DUMP (with decompilation) ══
local function tryEnvironment(obj)
    if not has.getsenv then return nil end
    local ok, env = pcall(getsenv, obj)
    if not ok or not env then return nil end
    local lines = {"-- [Environment dump with function decompilation]"}
    local count = 0
    pcall(function()
        for k, v in pairs(env) do
            count = count + 1; if count > 100 then break end
            if type(v) == "function" and has.decompile then
                lines[#lines+1] = string.format("-- %s = <function>", tostring(k))
                pcall(function()
                    local ok2, src2 = C.timedCall(decompile, 3, v)
                    if ok2 and type(src2) == "string" and #src2 > 2 then
                        lines[#lines+1] = "function "..tostring(k).."(...)"; lines[#lines+1] = src2; lines[#lines+1] = "end"
                    end
                end)
            else
                lines[#lines+1] = string.format("-- %s = %s [%s]", tostring(k), tostring(v):sub(1,200), type(v))
            end
        end
    end)
    if count > 0 then return table.concat(lines, "\n"), "senv" end
    return nil
end

-- ══ 11: BYTECODE DUMP ══
local function tryBytecode(obj)
    if not has.getscriptbytecode then return nil end
    local ok, bc = pcall(getscriptbytecode, obj)
    if not ok or not bc or #bc == 0 then return nil end
    local encoded
    if D.base64enc then pcall(function() encoded = D.base64enc(bc) end) end
    if encoded and #encoded > 0 then
        return string.format("-- [Bytecode: %d bytes]\n-- Base64:\n--[[\n%s\n--]]", #bc, encoded), "bytecode_b64"
    end
    return string.format("-- [Bytecode: %d bytes — raw]", #bc), "bytecode_raw"
end

-- ══ 12: GETSCRIPTFUNCTION ══
local function tryGetScriptFunction(obj)
    if not has.getscriptfunction or not has.decompile then return nil end
    local fn; pcall(function() fn = getscriptfunction(obj) end)
    if not fn then return nil end
    local ok, src = C.timedCall(decompile, math.max(D.limits.decompileTimeout - 2, 3), fn)
    if ok and type(src) == "string" and #src > 2 then return src, "scriptfunction" end
    return nil
end

-- ══ 13: GC CLOSURE MATCH ══
local function tryGCClosureMatch(obj)
    if not has.getgc or not has.decompile then return nil end
    local objId; pcall(function() objId = tostring(obj) end)
    if not objId then return nil end
    local gc; pcall(function() gc = getgc(false) end)
    if not gc then return nil end
    local lines = {"-- [GC Closure Match — functions belonging to this script]", ""}
    local found = 0
    local sz = math.min(#gc, 20000)
    for i = 1, sz do
        if found >= 15 then break end
        pcall(function()
            if type(gc[i]) == "function" then
                local e = getfenv(gc[i])
                if e then
                    local s = rawget(e, "script")
                    if s and tostring(s) == objId then
                        found = found + 1
                        local ok2, src2 = C.timedCall(decompile, 3, gc[i])
                        if ok2 and type(src2) == "string" and #src2 > 2 then
                            lines[#lines+1] = "-- ── GC Function #"..found.." ──"
                            lines[#lines+1] = src2; lines[#lines+1] = ""
                        end
                    end
                end
            end
        end)
    end
    gc = nil
    if found > 0 then return table.concat(lines, "\n"), "gc_closure_match" end
    return nil
end

-- ══ 14: THREAD DECOMPILE ══
local function tryThreadDecompile(obj)
    if not has.getgc or not has.getscriptfromthread or not has.decompile then return nil end
    local objId; pcall(function() objId = tostring(obj) end)
    if not objId then return nil end
    local gc; pcall(function() gc = getgc(true) end)
    if not gc then return nil end
    local lines = {"-- [Thread Decompile — functions from script threads]", ""}
    local found = 0
    local sz = math.min(#gc, 15000)
    for i = 1, sz do
        if found >= 10 then break end
        if type(gc[i]) == "thread" then
            pcall(function()
                local s = getscriptfromthread(gc[i])
                if s and tostring(s) == objId then
                    local info; pcall(function() info = debug.info(gc[i], 1, "f") end)
                    if info and type(info) == "function" then
                        local ok2, src2 = C.timedCall(decompile, 3, info)
                        if ok2 and type(src2) == "string" and #src2 > 2 then
                            found = found + 1
                            lines[#lines+1] = "-- ── Thread Func #"..found.." ──"
                            lines[#lines+1] = src2; lines[#lines+1] = ""
                        end
                    end
                end
            end)
        end
    end
    gc = nil
    if found > 0 then return table.concat(lines, "\n"), "thread_decompile" end
    return nil
end

-- ══ 15: FULL RECONSTRUCTION ══
local function tryFullReconstruction(obj)
    if not has.getscriptclosure then return nil end
    local fn; pcall(function() fn = getscriptclosure(obj) end)
    if not fn then return nil end
    local lines = {"-- [Full Reconstruction — combined analysis]", ""}
    local hasAny = false

    -- Debug info header
    if has["debug.getinfo"] then
        pcall(function()
            local di = debug.getinfo(fn)
            if di then
                hasAny = true
                lines[#lines+1] = "-- ═══ Script Info ═══"
                if di.source then lines[#lines+1] = "-- Source: "..tostring(di.source):sub(1,200) end
                if di.numparams or di.nparams then lines[#lines+1] = "-- Params: "..tostring(di.numparams or di.nparams) end
                if di.linedefined then lines[#lines+1] = "-- Lines: "..di.linedefined.."-"..(di.lastlinedefined or "?") end
                lines[#lines+1] = ""
            end
        end)
    end

    -- All constants with categorization
    if has.getconstants then
        pcall(function()
            local consts = getconstants(fn)
            if consts and #consts > 0 then
                hasAny = true
                local strings, numbers, funcs = {}, {}, {}
                for _, c in ipairs(consts) do
                    if type(c) == "string" and #c > 0 then strings[#strings+1] = c:sub(1,80)
                    elseif type(c) == "number" then numbers[#numbers+1] = c end
                end
                if #strings > 0 then
                    lines[#lines+1] = "-- ═══ String Constants ("..#strings..") ═══"
                    for _, s in ipairs(strings) do lines[#lines+1] = '-- "'..s:gsub("\n","\\n")..'"' end
                    lines[#lines+1] = ""
                end
                if #numbers > 0 then
                    lines[#lines+1] = "-- ═══ Number Constants ("..#numbers..") ═══"
                    for _, n in ipairs(numbers) do lines[#lines+1] = "-- "..tostring(n) end
                    lines[#lines+1] = ""
                end
            end
        end)
    end

    -- Upvalues with types
    if has.getupvalues then
        pcall(function()
            local ups = getupvalues(fn)
            if ups then
                hasAny = true; local ct = 0
                lines[#lines+1] = "-- ═══ Upvalues ═══"
                for k, v in pairs(ups) do
                    ct = ct + 1; if ct > 50 then break end
                    if type(v) == "function" and has.decompile then
                        lines[#lines+1] = string.format("-- [%s] <function>", tostring(k))
                        pcall(function()
                            local ok2, s2 = C.timedCall(decompile, 2, v)
                            if ok2 and type(s2) == "string" and #s2 > 2 then lines[#lines+1] = s2 end
                        end)
                    else
                        lines[#lines+1] = string.format("-- [%s] <%s> = %s", tostring(k), type(v), tostring(v):sub(1,120))
                    end
                end
                lines[#lines+1] = ""
            end
        end)
    end

    -- Protos summary
    if has.getprotos then
        pcall(function()
            local protos = getprotos(fn)
            if protos and #protos > 0 then
                hasAny = true
                lines[#lines+1] = "-- ═══ Sub-functions ("..#protos..") ═══"
                for pi, proto in ipairs(protos) do
                    if pi > 50 then lines[#lines+1] = "-- ... ("..(#protos-50).." more)"; break end
                    pcall(function()
                        if has.decompile then
                            local ok2, s2 = C.timedCall(decompile, 2, proto)
                            if ok2 and type(s2) == "string" and #s2 > 2 then
                                lines[#lines+1] = "-- ── Sub #"..pi.." ──"
                                lines[#lines+1] = s2; lines[#lines+1] = ""
                            end
                        end
                    end)
                end
            end
        end)
    end

    if hasAny then return table.concat(lines, "\n"), "full_reconstruction" end
    return nil
end

-- ══ IDENTIFY SCRIPT ══
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

-- ══ PROCESS ONE — v15: 16 strategies ══
function M.processOne(entry)
    if D.S.cancel then return end
    local obj = entry.inst
    if not obj then D.S.stats.fail = D.S.stats.fail + 1; return end

    local name, path = "?", "?"
    pcall(function() name = obj.Name end)
    pcall(function() path = obj:GetFullName() end)

    local source, method

    -- 1. Cache
    source, method = tryCache(obj, entry)
    -- 2. Decompile
    if not source then source, method = tryDecompile(obj) end
    -- 3. Script.Source
    if not source then source, method = tryScriptSource(obj) end
    -- 4. Closure decompile
    if not source then pcall(function() source, method = tryClosure(obj) end)
        if source then D.S.stats.aggressive = D.S.stats.aggressive + 1 end end
    -- 5. Clone + decompile
    if not source then pcall(function() source, method = tryCloneDecompile(obj) end)
        if source then D.S.stats.aggressive = D.S.stats.aggressive + 1 end end
    -- 12. getscriptfunction
    if not source then pcall(function() source, method = tryGetScriptFunction(obj) end)
        if source then D.S.stats.aggressive = D.S.stats.aggressive + 1 end end
    -- 6. Protos (recursive, unlimited)
    if not source then pcall(function() source, method = tryGetProtos(obj) end)
        if source then D.S.stats.aggressive = D.S.stats.aggressive + 1 end end
    -- 13. GC Closure Match
    if not source then pcall(function() source, method = tryGCClosureMatch(obj) end)
        if source then D.S.stats.aggressive = D.S.stats.aggressive + 1 end end
    -- 14. Thread Decompile
    if not source then pcall(function() source, method = tryThreadDecompile(obj) end)
        if source then D.S.stats.aggressive = D.S.stats.aggressive + 1 end end
    -- 7. Constants/Upvalues
    if not source then pcall(function() source, method = tryConstantsReconstruct(obj) end)
        if source then D.S.stats.aggressive = D.S.stats.aggressive + 1 end end
    -- 8. Debug info stub
    if not source then pcall(function() source, method = tryDebugInfo(obj) end)
        if source then D.S.stats.aggressive = D.S.stats.aggressive + 1 end end
    -- 9. Require force (recursive)
    if not source then pcall(function() source, method = tryRequireForce(obj) end)
        if source then D.S.stats.aggressive = D.S.stats.aggressive + 1 end end
    -- 15. Full Reconstruction
    if not source then pcall(function() source, method = tryFullReconstruction(obj) end)
        if source then D.S.stats.aggressive = D.S.stats.aggressive + 1 end end
    -- 10. Environment dump
    if not source then pcall(function() source, method = tryEnvironment(obj) end)
        if source then D.S.stats.aggressive = D.S.stats.aggressive + 1 end end
    -- 11. Bytecode
    if not source then source, method = tryBytecode(obj)
        if source then D.S.stats.aggressive = D.S.stats.aggressive + 1 end end

    if source then
        if entry.bcHash and entry.bcHash ~= "EMPTY" and method ~= "cache" then
            D.cache.bytecode[entry.bcHash] = source
        end
        local header = string.format(
            "%s-- Script: %s\n-- Path: %s\n-- Method: %s [v15 — 16 strategies]\n-- Source: %s\n-- Extracted: %s\n\n",
            LOGO, name, path, method, entry.from or "?", os.date("%Y-%m-%d %H:%M:%S")
        )
        local fullSource = header .. source
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

    if (D.S.stats.ok + D.S.stats.fail) % 5 == 0 then C.push() end
end

end