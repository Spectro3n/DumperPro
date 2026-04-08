local BASE = ... or "https://raw.githubusercontent.com/Spectro3n/DumperPro/main/src/"

local UI = loadstring(game:HttpGet(
    "https://raw.githubusercontent.com/Spectro3n/DumperUI/refs/heads/main/DumperUI.lua"
))()

local D = { UI = UI }

local moduleStatus = {}

local function loadMod(name, required)
    local ok, err = pcall(function()
        local code = game:HttpGet(BASE..name..".lua")
        local fn = loadstring(code)()
        fn(D)
    end)
    moduleStatus[name] = ok
    if not ok then
        UI:Log("⚠ Module "..name.." failed: "..tostring(err):sub(1,80), "red")
        if required then UI:Log("CRITICAL — cannot continue without "..name, "red") end
    end
    task.wait(0.1)
    return ok
end

if not loadMod("core", true) then return end
if not loadMod("decompile", true) then return end
if not loadMod("collect", true) then return end
loadMod("hooks", false)
loadMod("output", false)

local C   = D.Core
local has = D.has

-- ══════════════════════════════════
--  PROCESSING ENGINE
-- ══════════════════════════════════

local processingThread = nil

local function onDone()
    if D.Output and D.Output.saveAll then D.Output.saveAll() end

    D.UI:SetPhase("done")
    D.UI:SetRunning(false)

    local stopped = D.S.cancel
    D.UI:SetBadge(stopped and "Stopped" or "Done", stopped and "red" or "green")
    D.UI:SetProgress(D.S.stats.ok+D.S.stats.fail, math.max(D.S.stats.queued,1))
    C.push()

    D.UI:Log("═══════════════════════════", "green")
    D.UI:Log(string.format("%s — %d/%d — cache:%d — aggressive:%d — %s",
        stopped and "STOPPED" or "DONE",
        D.S.stats.ok, D.S.stats.total,
        D.S.cacheStats.hits, D.S.stats.aggressive,
        C.elapsed()), "green")
    D.UI:Log("Folder: "..D.S.rootDir.."/", "green")
    D.UI:Log("═══════════════════════════", "green")
    D.UI:SetStatus("✓ "..D.S.stats.ok.."/"..D.S.stats.total.." · "..C.elapsed())
end

local function startProcessing()
    D.UI:SetPhase("decompiling")
    D.UI:Log("Processing "..#D.S.queue.." scripts...", "blue")

    local mode = D.cfg.mode or "normal"
    local batchSize = D.limits.batchSize
    local cacheHitBatch = D.limits.cacheHitBatch
    local memCheckEvery = D.limits.memCheckEvery
    local gcStep = D.limits.gcStepSize
    local logEvery = D.limits.logEvery

    processingThread = task.spawn(function()
        local batch = 0
        local cacheStreak = 0

        while #D.S.queue > 0 and not D.S.cancel do
            local entry = table.remove(D.S.queue, 1)
            local isCacheHit = entry.bcHash
                and entry.bcHash ~= "EMPTY"
                and D.cache.bytecode[entry.bcHash]

            D.Decompile.processOne(entry)
            batch = batch + 1

            if batch % logEvery == 0 then
                D.UI:Log(string.format("  %d/%d (%d cached, %d fail) %s",
                    D.S.stats.ok+D.S.stats.fail, D.S.stats.queued,
                    D.S.cacheStats.hits, D.S.stats.fail, C.elapsed()), "gray")
            end

            -- Yield: mode-adaptive
            if mode == "turbo" then
                if isCacheHit then
                    cacheStreak = cacheStreak + 1
                    if cacheStreak >= cacheHitBatch then cacheStreak = 0; task.wait() end
                else
                    cacheStreak = 0
                    if batch % batchSize == 0 then task.wait() end
                end
            elseif mode == "safe" then
                -- Safe: always yield, always check memory
                task.wait()
                if batch % memCheckEvery == 0 then
                    if not C.memoryGuard() then
                        D.UI:Log("⚠ Memory limit — pausing 2s","red")
                        task.wait(2)
                        pcall(collectgarbage,"collect")
                        if not C.memoryGuard() then
                            D.UI:Log("⚠ Still critical — saving what we have","red")
                            break
                        end
                    end
                end
            else
                if isCacheHit then
                    if batch % (batchSize * 5) == 0 then task.wait() end
                else
                    if batch % batchSize == 0 then task.wait() end
                end
            end

            if batch % memCheckEvery == 0 then
                pcall(collectgarbage, "step", gcStep)
                C.memoryGuard()
            end
        end

        onDone()
        processingThread = nil
    end)
end

-- ══════════════════════════════════
--  START DUMP
-- ══════════════════════════════════

local function startDump()
    D.cfg = UI:GetConfig()
    C.resetState()

    D.UI:SetRunning(true)
    D.UI:ClearLog()
    D.UI:SetProgress(0, 1)

    local mode = D.cfg.mode or "normal"

    D.UI:Log("═══════════════════════════", "blue")
    D.UI:Log("DUMP PRO v13: "..D.S.rootDir, "blue")
    D.UI:Log("Mode: "..mode:upper().." — ALL SCANNERS ACTIVE", "blue")
    D.UI:Log("Limits: yield="..D.limits.yieldEvery
        .." gc="..D.limits.gcLimit
        .." timeout="..D.limits.decompileTimeout.."s"
        .." batch="..D.limits.batchSize
        .." depth="..D.limits.upvalueDepth, "blue")
    D.UI:Log("Single file: "..tostring(D.S.isSingleFile), "blue")
    D.UI:Log("Cache: "..(next(D.cache.bytecode) and "WARM" or "cold"), "blue")
    D.UI:Log("Memory: "..math.floor(C.getMemKB()/1024).."MB", "blue")

    local mods = {}
    for name, ok in pairs(moduleStatus) do mods[#mods+1] = name..(ok and "✓" or "✗") end
    D.UI:Log("Modules: "..table.concat(mods," "), "blue")
    D.UI:Log("═══════════════════════════", "blue")

    D.Collect.collectAll()

    if D.S.cancel then
        D.UI:SetRunning(false); D.UI:SetBadge("Stopped","red"); return
    end

    if D.Hooks and D.Hooks.analyze then
        C.memoryGuard(); task.wait(0.15)
        C.safeScan("Hooks", function() D.Hooks.analyze() end)
    end

    if D.S.cancel then
        D.UI:SetRunning(false); D.UI:SetBadge("Stopped","red"); return
    end

    if #D.S.queue == 0 then
        D.UI:Log("No scripts found", "yellow")
        onDone(); return
    end

    startProcessing()
end

-- ══════════════════════════════════
--  UI WIRING
-- ══════════════════════════════════

UI.OnStart = function()
    if processingThread then return end
    task.spawn(startDump)
end

UI.OnStop = function()
    D.S.cancel = true
    D.UI:Log("Stopping...", "yellow")
end

UI.OnSaveInstance = function()
    if not has.saveinstance then D.UI:Log("saveinstance unavailable","red"); return end
    D.UI:Log("Running saveinstance...","blue")
    D.UI:SetBadge("Saving","yellow")
    task.spawn(function()
        local ok, err = pcall(saveinstance, {
            ExcludePlayerGui=false, DecompileTimeout=30,
            NilInstances=true, RemovePlayerNames=true,
        })
        if ok then D.UI:Log("Done","green"); D.UI:SetBadge("Done","green")
        else D.UI:Log("Error: "..tostring(err),"red"); D.UI:SetBadge("Error","red") end
    end)
end

local caps = 0
for _, v in pairs(has) do if v then caps = caps + 1 end end

UI:Log("Dumper Pro v13 — Maximum Discovery", "green")
UI:Log("Game: "..UI:GetConfig().folder, "gray")
UI:Log("Caps: "..caps.."/"..#C.PROBES, "gray")
UI:Log("ALL scanners run in ALL modes", "white")
UI:Log("★ Safe: max protection (yields+memchecks), same coverage", "gray")
UI:Log("★ Normal: balanced speed + protection", "gray")
UI:Log("★ Turbo: max speed, chunk processing, cache bursts", "gray")
UI:Log("Press START", "white")