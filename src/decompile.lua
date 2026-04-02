return function(D)
local M = {}
D.Decompile = M
local C, has = D.Core, D.has

-- ══ IDENTIFY SCRIPT (fast, 4 methods — sem upvalue walk) ══
function M.identifyScript(fn)
    if not fn or type(fn)~="function" then return "~none","none","?" end
    local path,name,cls = "unknown","unknown","?"

    pcall(function()
        local env = getfenv(fn)
        if env then
            local s = rawget(env,"script")
            if s and typeof(s)=="Instance" then
                path=s:GetFullName(); name=s.Name; cls=s.ClassName
            end
        end
    end)
    if path~="unknown" then return path,name,cls end

    pcall(function()
        local src = debug.info(fn,"s")
        local ln  = debug.info(fn,"l")
        if src and src~="" and src~="[C]" and src~="=[C]" then
            path = src..(ln and (":"..ln) or "")
            name = src:match("([^%.]+)$") or src
        end
    end)
    if path~="unknown" then return path,name,cls end

    pcall(function()
        local n = debug.info(fn,"n")
        if n and n~="" then path="~func:"..n; name=n end
    end)
    if path~="unknown" then return path,name,cls end

    pcall(function()
        if has.iscclosure and iscclosure(fn) then
            path="~C"; name="C_closure"; cls="C"
        else
            path="~lua:"..(tostring(fn):match("0x%x+") or "?")
            name="lua"
        end
    end)
    return path,name,cls
end

-- ══ EXTRACTION HELPERS ══
function M.extractConstants(fn)
    if not has.getconstants then return nil end
    local ok,consts = pcall(getconstants, fn)
    if not ok or not consts or #consts==0 then return nil end
    local lines = {"-- [CONSTANTS] ("..#consts..")"}
    for i,c in ipairs(consts) do
        if i>400 then lines[#lines+1]="-- ... +"..#consts-400; break end
        local t=type(c)
        if t=="string" then
            lines[#lines+1]=string.format("--  [%d] %q",i,c:sub(1,150))
        elseif t=="number" or t=="boolean" then
            lines[#lines+1]=string.format("--  [%d] %s",i,tostring(c))
        end
    end
    return #lines>1 and table.concat(lines,"\n") or nil
end

function M.extractUpvalues(fn)
    if not has.getupvalues then return nil end
    local ok,ups = pcall(getupvalues, fn)
    if not ok or not ups then return nil end
    local count=0; for _ in pairs(ups) do count=count+1 end
    if count==0 then return nil end
    local lines = {"-- [UPVALUES] ("..count..")"}
    local n=0
    for idx,val in pairs(ups) do
        n=n+1; if n>60 then lines[#lines+1]="-- ... +"..count-60; break end
        local t,disp = type(val),"?"
        if t=="string" then disp=string.format("%q",val:sub(1,150))
        elseif t=="table" then
            local tc=0; for _ in pairs(val) do tc=tc+1; if tc>50 then break end end
            disp = "{#"..tc.."}"
        elseif t=="function" then
            local nOk,nm = pcall(debug.info,val,"n")
            disp = "function "..(nOk and nm~="" and nm or "anon")
        elseif typeof(val)=="Instance" then disp=C.safeName(val)
        else disp=tostring(val):sub(1,80) end
        lines[#lines+1]=string.format("--  [%s] (%s) = %s",tostring(idx),t,disp)
    end
    return table.concat(lines,"\n")
end

function M.extractProtos(fn)
    if not has.getprotos then return nil end
    local ok,plist = pcall(getprotos, fn)
    if not ok or not plist or #plist==0 then return nil end
    local lines = {"-- [PROTOS] ("..#plist..")"}
    for i,proto in ipairs(plist) do
        if i>25 then lines[#lines+1]="-- ... +"..#plist-25; break end
        local nOk,nm = pcall(debug.info,proto,"n")
        local sOk,src = pcall(debug.info,proto,"s")
        lines[#lines+1]=string.format("-- #%d %s | src=%s", i,
            (nOk and nm~="" and nm or "anon"), sOk and src or "?")
        if has.getconstants then
            pcall(function()
                local pc=getconstants(proto); if not pc then return end
                local strs={}
                for ci,c in ipairs(pc) do
                    if ci>40 then break end
                    if type(c)=="string" and #c>0 and #c<80 then strs[#strs+1]=string.format("%q",c) end
                end
                if #strs>0 then lines[#lines+1]="--   Consts: "..table.concat(strs,", ") end
            end)
        end
        if has.decompile then
            local ok2,s = C.timedCall(decompile, 4, proto)
            if ok2 and type(s)=="string" and #s>10 then
                local lc=0
                for line in s:gmatch("[^\n]+") do
                    lc=lc+1; if lc>40 then lines[#lines+1]="--   ..."; break end
                    lines[#lines+1]="--   "..line
                end
            end
        end
    end
    return table.concat(lines,"\n")
end

function M.extractDebugInfo(fn)
    local lines={"-- [DEBUG INFO]"}
    pcall(function() local n=debug.info(fn,"n"); lines[#lines+1]="-- Name: "..((n and n~="") and n or "(anon)") end)
    pcall(function() local s=debug.info(fn,"s"); lines[#lines+1]="-- Source: "..(s or "?") end)
    pcall(function() local l=debug.info(fn,"l"); lines[#lines+1]="-- Line: "..tostring(l) end)
    pcall(function() local a,v=debug.info(fn,"a"); lines[#lines+1]="-- Args: "..tostring(a).." Vararg: "..tostring(v) end)
    if has.iscclosure then pcall(function() lines[#lines+1]="-- Type: "..(iscclosure(fn) and "C" or "Lua") end) end
    return table.concat(lines,"\n")
end

function M.aggressiveAnalysis(fn, obj)
    local parts = {
        "-- ═══════════════════════════════════",
        "-- [AGGRESSIVE ANALYSIS]",
        "-- Script: "..C.safeName(obj),
        "-- ═══════════════════════════════════","",
    }
    local dbi = M.extractDebugInfo(fn); if dbi then parts[#parts+1]=dbi; parts[#parts+1]="" end
    local co = M.extractConstants(fn);  if co then parts[#parts+1]=co; parts[#parts+1]="" end
    local up = M.extractUpvalues(fn);   if up then parts[#parts+1]=up; parts[#parts+1]="" end
    local pr = M.extractProtos(fn);     if pr then parts[#parts+1]=pr end
    return #parts>6 and table.concat(parts,"\n") or nil
end

-- ══ LINKED SOURCE ══
function M.tryLinkedSource(obj)
    local ok,url = pcall(function() return obj.LinkedSource end)
    if not ok or not url or url=="" then return nil end
    local id = url:match("%w+$"); if not id then return nil end
    if D.cache.linked[id] then return D.cache.linked[id],"linkedsrc_cached" end
    local qt = id:find("%a") and "hash" or "id"
    local fok,src = pcall(function() return game:HttpGet("https://assetdelivery.roproxy.com/v1/asset/?"..qt.."="..id) end)
    if not fok or not src or #src<=4 then return nil end
    local jok,j = pcall(D.Core.Http.JSONDecode, D.Core.Http, src)
    if jok and type(j)=="table" and j.errors then return nil end
    D.cache.linked[id]=src
    return src,"linkedsource"
end

-- ══ DECOMPILE CHAIN ══
function M.tryDecompile(obj, entry)
    local bcHash = entry and entry.bcHash or C.getScriptHash(obj)

    if bcHash and bcHash~="EMPTY" and D.cache.bytecode[bcHash] then
        D.S.cacheStats.hits=D.S.cacheStats.hits+1
        D.S.stats.cache_hits=D.S.stats.cache_hits+1
        C.trackMethod("cache_hit")
        return D.cache.bytecode[bcHash],"cache_hit"
    end

    if C.isServerScript(obj) then C.trackMethod("server"); return "-- [SERVER] FilteringEnabled","server" end
    if bcHash=="EMPTY" then C.trackMethod("empty"); return "-- Empty Script","empty" end

    local ls,lm = M.tryLinkedSource(obj)
    if ls then
        if bcHash then D.cache.bytecode[bcHash]=ls end
        D.S.stats.linked=D.S.stats.linked+1; C.trackMethod(lm); return ls,lm
    end

    -- decompile direto
    if has.decompile then
        local ok,src = C.timedCall(decompile, D.limits.decompileTimeout, obj)
        if ok and type(src)=="string" and #src>4 then
            local bad = src:find("Failed to decompile",1,true) or (src:find("Error:",1,true) and #src<100)
            if not bad then
                src=src:gsub("%z","\\0")
                if bcHash then D.cache.bytecode[bcHash]=src; D.S.cacheStats.misses=D.S.cacheStats.misses+1 end
                C.trackMethod("decompile"); return src,"decompile"
            end
        end
    end

    -- closure decompile
    if has.getscriptclosure and has.decompile then
        local ok1,cl = pcall(getscriptclosure, obj)
        if ok1 and cl then
            local ok2,src = C.timedCall(decompile, D.limits.decompileTimeout/2, cl)
            if ok2 and type(src)=="string" and #src>4 and not src:find("Failed",1,true) then
                src=src:gsub("%z","\\0")
                if bcHash then D.cache.bytecode[bcHash]=src end
                C.trackMethod("closure"); return src,"closure"
            end
        end
    end

    -- senv
    if has.getsenv then
        pcall(function()
            if not obj:IsA("LocalScript") then return end
            local ok,env = pcall(getsenv, obj)
            if not ok or type(env)~="table" or not next(env) then return end
            local parts,found = {"-- [ENVIRONMENT DUMP]","-- "..C.safeName(obj),""},false
            local ec=0
            for k,v in pairs(env) do
                ec=ec+1; if ec>80 then break end
                if type(v)=="function" and has.decompile then
                    local ok2,s2 = C.timedCall(decompile,5,v)
                    if ok2 and type(s2)=="string" and #s2>4 then
                        parts[#parts+1]="-- fn: "..tostring(k); parts[#parts+1]=s2:gsub("%z","\\0"); found=true
                    end
                elseif type(v)~="function" then
                    parts[#parts+1]="-- "..tostring(k).." = "..tostring(v):sub(1,80); found=true
                end
            end
            if found then
                local r=table.concat(parts,"\n")
                if bcHash then D.cache.bytecode[bcHash]=r end
                C.trackMethod("senv"); return r,"senv" -- nota: não retorna de tryDecompile
            end
        end)
        -- checa se senv produziu resultado (workaround para return dentro de pcall)
        if bcHash and D.cache.bytecode[bcHash] and D.S.stats.methods.senv then
            return D.cache.bytecode[bcHash], "senv"
        end
    end

    -- aggressive analysis
    local targetFunc
    if has.getscriptclosure then pcall(function() targetFunc=getscriptclosure(obj) end) end
    if not targetFunc and has.getscriptfunction then pcall(function() targetFunc=getscriptfunction(obj) end) end

    if targetFunc then
        local analysis = M.aggressiveAnalysis(targetFunc, obj)
        if analysis then
            if bcHash then D.cache.bytecode[bcHash]=analysis end
            D.S.stats.aggressive=D.S.stats.aggressive+1; C.trackMethod("aggressive")
            return analysis,"aggressive"
        end
    end

    -- bytecode dump
    if has.getscriptbytecode then
        local ok,bc = pcall(getscriptbytecode, obj)
        if ok and bc and #bc>0 then
            local out = string.format("-- [BYTECODE — %d bytes]\n-- %s\n",#bc,C.safeName(obj))
            if D.base64enc then
                local eOk,enc = pcall(D.base64enc, bc)
                if eOk and enc then out=out.."-- B64: "..enc.."\n" end
            end
            if targetFunc then
                local co = M.extractConstants(targetFunc)
                if co then out=out.."\n"..co end
            end
            C.trackMethod("bytecode"); return out,"bytecode"
        end
    end

    -- source property
    local ok3,raw = pcall(function() return obj.Source end)
    if ok3 and type(raw)=="string" and #raw>4 then
        if bcHash then D.cache.bytecode[bcHash]=raw end
        C.trackMethod("source_prop"); return raw,"source_prop"
    end

    C.trackMethod("failed"); return nil,"failed"
end

-- ══ PROCESS ONE ══
function M.processOne(entry)
    local obj,from = entry.inst, entry.from
    local src,method = M.tryDecompile(obj, entry)

    if not src then
        D.S.stats.fail=D.S.stats.fail+1
        D.S.fails[#D.S.fails+1] = string.format("[%s] %s (%s)",
            pcall(function() return obj.ClassName end) and obj.ClassName or "?",
            C.safeName(obj), from)
        C.push(); return
    end

    D.S.stats.ok=D.S.stats.ok+1
    local h = {"-- ═══════════════════════════════════"}
    h[#h+1]="-- #"..D.S.stats.ok.."  "..(pcall(function() return obj.Name end) and obj.Name or "?")
    h[#h+1]="-- Path:   "..C.safeName(obj)
    h[#h+1]="-- Class:  "..(pcall(function() return obj.ClassName end) and obj.ClassName or "?")
    h[#h+1]="-- Found:  "..from
    h[#h+1]="-- Method: "..method
    if method=="cache_hit" then h[#h+1]="-- Cache: HIT" end
    if method=="aggressive" then h[#h+1]="-- Note: Decompile failed — extracted data" end
    pcall(function() h[#h+1]="-- Parent: "..(obj.Parent and C.safeName(obj.Parent) or "nil") end)
    if has.getscripthash then pcall(function() h[#h+1]="-- Hash: "..getscripthash(obj) end) end
    h[#h+1]="-- ═══════════════════════════════════"

    local content = table.concat(h,"\n").."\n\n"..src

    if D.S.isSingleFile then
        D.S.singleBuffer[#D.S.singleBuffer+1]=content.."\n\n"
    else
        local folder,fileName = C.buildFilePath(obj)
        C.writeFile(folder.."/"..fileName..".lua", content)
    end

    C.push()
    if D.S.stats.ok%12==0 then pcall(collectgarbage,"step",200) end
end

end