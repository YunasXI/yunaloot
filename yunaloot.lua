--[[
YunaLoot - Copyright (C) 2026 Yunas - https://github.com/YunasXI
Auto lot / auto pass for the treasure pool (FINAL FANTASY XI, CatsEyeXI). Runs on VanaCore and on Ashita v4.

    /yloot lot     every item that drops is lotted once
    /yloot pass    every item that drops is passed once
    /yloot off     off: you choose (every login starts here)
    /yloot         says which one is on

Rules it keeps, so nothing it sends is refused by the server (asked by the CatsEyeXI GMs):
  - one lot or pass per item, ever - and none at all if one already left this game for that item (yours in the game's
    menu, or another addon's);
  - nothing while you're knocked out;
  - no lot when your inventory is full (Auto lot waits, and lots it once there's room, while it's still in the pool);
  - no lot on a Rare item you already have (any bag, wardrobe or Mog House storage);
  - an item is only acted on 0.8 s after it lands, and the pool is read again right before sending - an item that
    only flashed through the pool (a fast cleave) is never lotted after it left.
--]]

addon.name    = 'yunaloot';
addon.author  = 'Yunas';
addon.version = '1.0.0';
addon.desc    = 'Auto lot or auto pass every treasure pool item, once, safely.';
addon.link    = 'https://github.com/YunasXI';

require('common');
local chat = require('chat');

local Y = {
    mode = 'off',      -- 'lot', 'pass' or 'off' - never saved: each login starts at off
    pool = {},         -- slot -> { id, key, mine }  (mine: your lot, -1 a pass, nil none)
    n = 0,
    seen = {},         -- item key -> when it was first seen
    done = {},         -- item key -> true: acted on (or decided not to)
    acted = {},        -- slot -> the key of the item YunaLoot lotted / passed there
    out = {},          -- slot -> { key, t }: a lot / pass packet that left this game (from anywhere)
    warned = {},       -- note key -> true: each note shown once per item
    t = 0,
    WAIT = 0.8,
};

local function msg(s) print(chat.header(addon.name):append(chat.message(s))); end

local function item_name(id)
    local nm = '';
    pcall(function() local r = AshitaCore:GetResourceManager():GetItemById(id); nm = (r and r.Name and r.Name[1]) or ''; end);
    return nm;
end

-- The treasure pool, as the game has it now
function Y.read()
    local pool, n = {}, 0;
    pcall(function()
        local inv = AshitaCore:GetMemoryManager():GetInventory();
        for slot = 0, 9 do
            local it = inv:GetTreasurePoolItem(slot);
            local id = it and tonumber(it.ItemId) or 0;
            if id > 0 and id ~= 65535 then
                local lot = tonumber(it.Lot) or 0;
                pool[slot] = { id = id, key = slot .. ':' .. id .. ':' .. tostring(it.DropTime or 0),
                               mine = (lot >= 65535) and -1 or ((lot > 0) and lot or nil) };
                n = n + 1;
            end
        end
    end);
    Y.pool, Y.n = pool, n;
    if n == 0 then Y.seen, Y.done, Y.acted, Y.out, Y.warned = {}, {}, {}, {}, {}; end
end

-- Has a lot / pass already been made on THIS item? (the game keeps your lot on the slot, not the item: a new item
-- landing in a slot YunaLoot just lotted shows that old lot for a moment)
function Y.handled(slot, it)
    local o = Y.out[slot];
    if o and (o.key == it.key or (o.key == nil and os.clock() - o.t < 5)) then return true; end   -- (a packet already went out for it)
    if it.mine == nil then return false; end
    local a = Y.acted[slot];
    return a == nil or a == it.key;                                  -- (lotted before YunaLoot saw it, or by YunaLoot: done; else the old item's lot)
end

function Y.dead()
    local dead = false;
    pcall(function()
        local mm = AshitaCore:GetMemoryManager();
        if (mm:GetParty():GetMemberHP(0) or 1) == 0 then dead = true; end
        local me = mm:GetParty():GetMemberTargetIndex(0) or 0;
        if me ~= 0 then local st = mm:GetEntity():GetStatus(me) or 0; if st == 2 or st == 3 then dead = true; end end
    end);
    return dead;
end

function Y.bag_full()
    local full = false;
    pcall(function()
        local inv = AshitaCore:GetMemoryManager():GetInventory();
        local used, max = inv:GetContainerCount(0) or 0, inv:GetContainerCountMax(0) or 0;
        full = max > 0 and used >= max;
    end);
    return full;
end

function Y.have_rare(id)
    local rare = false;
    pcall(function()
        local r = AshitaCore:GetResourceManager():GetItemById(id);
        rare = r ~= nil and bit.band(tonumber(r.Flags) or 0, 0x8000) ~= 0;
    end);
    if not rare then return false; end
    local have = false;
    pcall(function()
        local inv = AshitaCore:GetMemoryManager():GetInventory();
        for c = 0, 16 do
            local max = 80;
            pcall(function() max = inv:GetContainerCountMax(c) or 80; end);
            for i = 0, max do
                local it = inv:GetContainerItem(c, i);
                if it and tonumber(it.Id) == id then have = true; return; end
            end
        end
    end);
    return have;
end

function Y.send(pid, slot)
    pcall(function() AshitaCore:GetPacketManager():AddOutgoingPacket(pid, { pid, 0x04, 0x00, 0x00, slot, 0x00, 0x00, 0x00 }); end);
end

-- Lot (true) or pass (false) one item, if the server would take it. Gives ok, and 'full' when the bag was full.
function Y.act(slot, lot)
    Y.read();                                                        -- (read again this moment: never after it left)
    local it = Y.pool[slot];
    if not it or Y.handled(slot, it) then return false; end
    local key = it.key .. (lot and ':l' or ':p');
    local function note(s) if not Y.warned[key] then Y.warned[key] = true; msg(s); end end
    if Y.dead() then note("You can't lot or pass while you're knocked out."); return false; end
    if lot and Y.bag_full() then note('Not lotted: ' .. item_name(it.id) .. ' - your inventory is full.'); return false, 'full'; end
    if lot and Y.have_rare(it.id) then note('Not lotted: ' .. item_name(it.id) .. ' is Rare and you already have one.'); return false; end
    Y.acted[slot] = it.key;
    Y.send(lot and 0x41 or 0x42, slot);
    return true;
end

function Y.tick()
    if os.clock() - Y.t < 0.05 then return; end
    Y.t = os.clock();
    Y.read();
    if Y.n == 0 or (Y.mode ~= 'lot' and Y.mode ~= 'pass') then return; end
    for slot, it in pairs(Y.pool) do
        Y.seen[it.key] = Y.seen[it.key] or os.clock();
        if not Y.done[it.key] and not Y.handled(slot, it) and os.clock() - Y.seen[it.key] >= Y.WAIT then
            Y.done[it.key] = true;
            local _, why = Y.act(slot, Y.mode == 'lot');
            if why == 'full' then Y.done[it.key] = nil; end          -- (inventory full: tried again once there's room)
        end
    end
end

-- A lot (0x041) or pass (0x042) leaving this game, from anywhere: remembered, so YunaLoot never sends a second one
function Y.on_out(e)
    if e.blocked then return; end
    local slot = struct.unpack('B', e.data, 0x04 + 1);
    if slot == nil or slot > 9 then return; end
    Y.read();
    local p = Y.pool[slot];
    Y.out[slot] = { key = p and p.key or nil, t = os.clock() };
end

----------------------------------------------------------------------------------------------------
-- The goblin: always on the screen, showing which one is on - coin eyes (they glint) = Auto lot, red X eyes = Auto
-- pass, grey = off. Click it to change (off -> lot -> pass -> off), drag it to move it. /yloot size 40..200.
----------------------------------------------------------------------------------------------------
local imgui = require('imgui');
local settings = require('settings');
local ffi = require('ffi');
local d3d = require('d3d8');
local G = {
    cfg = settings.load(T{ x = -1, y = -1, size = 96 }),
    tex = {},
    pop = 0,           -- when it last changed: a little bounce
    W = 242, H = 214,  -- the pictures' size (images\goblin_*.png)
    -- the coin eyes on the Auto lot goblin: centre and radius, as parts of the picture's width / height
    EYES = { { 0.4624, 0.4381, 0.076 }, { 0.6793, 0.4584, 0.070 } },
};
function G.texture(mode, size)
    local file = mode;                                               -- (the copy made for that size: sharp, never shrunk much by the GPU)
    for _, s in ipairs({ 64, 96, 128, 176 }) do if size <= s * 1.1 then file = mode .. '_' .. s; break; end end
    local name = file;
    if G.tex[name] ~= nil then return G.tex[name] or nil; end
    G.tex[name] = false;
    pcall(function()
        local f = io.open(addon.path .. '\\images\\goblin_' .. name .. '.png', 'rb');
        if f == nil then return; end
        local data = f:read('*a');
        f:close();
        local ptr = ffi.new('IDirect3DTexture8*[1]');
        if ffi.C.D3DXCreateTextureFromFileInMemoryEx(d3d.get_device(), data, #data, 0xFFFFFFFF, 0xFFFFFFFF, 1, 0,
                ffi.C.D3DFMT_A8R8G8B8, ffi.C.D3DPOOL_MANAGED, ffi.C.D3DX_DEFAULT, ffi.C.D3DX_DEFAULT, 0, nil, nil, ptr) == ffi.C.S_OK then
            local t = d3d.gc_safe_release(ffi.cast('IDirect3DTexture8*', ptr[0]));
            G.tex[name] = { t = t, ptr = tonumber(ffi.cast('uint32_t', t)) };
        end
    end);
    return G.tex[name] or nil;
end
function G.set(mode)
    Y.mode = mode;
    if mode ~= 'off' then Y.done = {}; end                           -- (items already in the pool count from now)
    G.pop = os.clock();
    msg(({ lot = 'Auto lot: ON', pass = 'Auto pass: ON', off = 'Auto lot / pass: OFF' })[mode]);
end
function G.col(r, g, b, a) return imgui.GetColorU32({ r, g, b, a }); end
-- A coin's glint: a bright band sweeping across it (kept inside the coin), then a small star sparkling on its rim
function G.glint(dl, cx, cy, r, t)
    if t < 0 or t > 0.9 then return; end
    local s2 = 0.70710678;
    if t < 0.55 then
        local p = -1.3 * r + (t / 0.55) * 2.6 * r;                   -- (where the band is, along the diagonal)
        local w = r * 0.40;
        for k = -w, w, 1 do
            local s = p + k;
            if math.abs(s) < r then
                local h = math.sqrt(r * r - s * s) * 0.96;
                local a = 0.80 * (1 - math.abs(k) / w) ^ 1.4;
                local mx, my = cx + s * s2, cy - s * s2;            -- (the band runs bottom-left to top-right)
                dl:AddLine({ mx - h * s2, my - h * s2 }, { mx + h * s2, my + h * s2 }, G.col(1, 0.97, 0.80, a), 1.2);
            end
        end
    end
    local st = (t - 0.35) / 0.55;                                    -- (the star: grows, then fades)
    if st > 0 and st < 1 then
        local a = math.sin(st * math.pi);
        local sx, sy = cx + r * 0.55, cy - r * 0.62;
        local L, w_ = r * 0.80 * a, r * 0.13 * a;
        local c = G.col(1, 1, 0.92, 0.95 * a);
        dl:AddTriangleFilled({ sx, sy - L }, { sx + w_, sy }, { sx - w_, sy }, c);
        dl:AddTriangleFilled({ sx, sy + L }, { sx - w_, sy }, { sx + w_, sy }, c);
        dl:AddTriangleFilled({ sx - L, sy }, { sx, sy - w_ }, { sx, sy + w_ }, c);
        dl:AddTriangleFilled({ sx + L, sy }, { sx, sy + w_ }, { sx, sy - w_ }, c);
        dl:AddCircleFilled({ sx, sy }, w_ * 1.6, G.col(1, 1, 1, 0.9 * a), 12);
    end
end
function G.draw()
    local name = '';
    pcall(function() name = AshitaCore:GetMemoryManager():GetParty():GetMemberName(0) or ''; end);
    if name == '' then return; end                                   -- (not logged in, or zoning)
    local cfg = G.cfg;
    local size = math.max(40, math.min(200, tonumber(cfg.size) or 96));
    local w, h = size, math.floor(size * G.H / G.W + 0.5);
    local io = imgui.GetIO();
    local sw, sh = io.DisplaySize.x, io.DisplaySize.y;
    if (tonumber(cfg.x) or -1) < 0 then cfg.x, cfg.y = math.floor(sw * 0.5 + 260), math.floor(sh * 0.70); end
    cfg.x = math.max(0, math.min(sw - w, cfg.x));                    -- (always on the screen)
    cfg.y = math.max(0, math.min(sh - h, cfg.y));
    imgui.SetNextWindowPos({ cfg.x, cfg.y }, ImGuiCond_Always);
    imgui.SetNextWindowSize({ w, h }, ImGuiCond_Always);
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, { 0, 0 });
    imgui.PushStyleVar(ImGuiStyleVar_WindowBorderSize, 0);
    local flags = bit.bor(ImGuiWindowFlags_NoDecoration, ImGuiWindowFlags_NoBackground, ImGuiWindowFlags_NoSavedSettings,
        ImGuiWindowFlags_NoMove, ImGuiWindowFlags_NoFocusOnAppearing, ImGuiWindowFlags_NoNav);
    if imgui.Begin('##yunaloot_goblin', true, flags) then
        local x0, y0 = imgui.GetCursorScreenPos();
        imgui.InvisibleButton('##yunaloot_btn', { w, h });
        local hov, act = imgui.IsItemHovered(), imgui.IsItemActive();
        if act and imgui.IsMouseDragging(0, 3) then                  -- (drag: it moves)
            local dx, dy = imgui.GetMouseDragDelta(0);
            if type(dx) == 'table' then dx, dy = dx.x, dx.y; end
            cfg.x, cfg.y = (G.dx0 or cfg.x) + dx, (G.dy0 or cfg.y) + dy;
            G.dragged = true;
        elseif imgui.IsItemActivated() then G.dx0, G.dy0, G.dragged = cfg.x, cfg.y, false; end
        if imgui.IsItemDeactivated() then
            if G.dragged then settings.save();                       -- (moved: kept for next time)
            else G.set(({ off = 'lot', lot = 'pass', pass = 'off' })[Y.mode] or 'off'); end   -- (a click: the next one)
            G.dragged = false;
        end
        local now = os.clock();
        local k = 1;
        local pt = now - G.pop;
        if pt < 0.35 then k = 1 + 0.14 * math.sin(pt / 0.35 * math.pi); end   -- (just changed: a little bounce)
        if hov and not act then k = k * 1.05; end
        local cx, cy = x0 + w / 2, y0 + h / 2;
        local hw, hh = w / 2 * k, h / 2 * k;
        local dl = imgui.GetWindowDrawList();
        local tx = G.texture(Y.mode == 'lot' and 'lot' or (Y.mode == 'pass' and 'pass' or 'off'), w);
        if tx then
            local a = (Y.mode == 'off') and 0.85 or 1;
            dl:AddImage(tx.ptr, { cx - hw, cy - hh }, { cx + hw, cy + hh }, { 0, 0 }, { 1, 1 }, G.col(1, 1, 1, a));
        end
        if Y.mode == 'lot' then                                      -- (the coin eyes glint, one after the other, every 2.8 s)
            local t = now % 2.8;
            for i, e in ipairs(G.EYES) do
                G.glint(dl, cx - hw + e[1] * hw * 2, cy - hh + e[2] * hh * 2, e[3] * hw * 2, t - (i - 1) * 0.18);
            end
        end
        if hov then
            imgui.SetTooltip(({ lot = 'YunaLoot: Auto lot ON', pass = 'YunaLoot: Auto pass ON', off = 'YunaLoot: off' })[Y.mode]
                .. '\nClick: change   Drag: move');
        end
    end
    imgui.End();
    imgui.PopStyleVar(2);
end

ashita.events.register('d3d_present', 'yunaloot_tick', function()
    pcall(Y.tick);
    local ok, err = pcall(G.draw);
    if not ok and G.err ~= tostring(err) then G.err = tostring(err); msg('Draw error: ' .. G.err); end
end);

ashita.events.register('packet_out', 'yunaloot_out', function(e)
    if e.id == 0x041 or e.id == 0x042 then pcall(Y.on_out, e); end
end);

ashita.events.register('command', 'yunaloot_cmd', function(e)
    local args = e.command:args();
    if #args == 0 or args[1]:lower() ~= '/yloot' then return; end
    e.blocked = true;
    local sub = (args[2] or ''):lower();
    if sub == 'lot' or sub == 'pass' or sub == 'off' then
        G.set(sub);
    elseif sub == 'size' and tonumber(args[3]) then                  -- (/yloot size 40..200: the goblin's width in pixels)
        G.cfg.size = math.max(40, math.min(200, math.floor(tonumber(args[3]))));
        settings.save();
        msg('Goblin size: ' .. G.cfg.size);
    elseif sub == '' then
        msg(({ lot = 'Auto lot: ON', pass = 'Auto pass: ON', off = 'Auto lot / pass: OFF' })[Y.mode] .. '  (/yloot lot, /yloot pass, /yloot off)');
    else
        msg('/yloot lot, /yloot pass or /yloot off');
    end
end);

YUNALOOT_TEST = Y;                                                   -- (for the safe test: tools\menu-test\yunaloot_test.lua)
