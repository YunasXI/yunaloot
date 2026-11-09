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
-- The goblin: always on the screen, showing which one is on - gold cap and coin eyes (they glint) = Auto lot, red X eyes = Auto
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
        local lit = Y.mode == 'lot';
        dl:PushClipRect({ 0, 0 }, { sw, sh }, false);                -- (a sparkle may reach past the goblin's box)
        local ang, py = 0, cy;                                       -- (Auto lot: the goblin bobs up and down and tilts a little, grinning,
        if lit then                                                  --  waiting for loot - no glow: the user didn't like it, 2026-11-09)
            py = cy - hh * 0.06 * (0.5 + 0.5 * math.sin(now * 2 * math.pi / 1.6));
            ang = 0.06 * math.sin(now * 2 * math.pi / 3.2);
        end
        local ca, sa = math.cos(ang), math.sin(ang);
        local function at(lx, ly) return { cx + lx * ca - ly * sa, py + lx * sa + ly * ca }; end   -- (a point of the picture, from its middle)
        if tx then
            local a = (Y.mode == 'off') and 0.85 or 1;
            dl:AddImageQuad(tx.ptr, at(-hw, -hh), at(hw, -hh), at(hw, hh), at(-hw, hh), { 0, 0 }, { 1, 0 }, { 1, 1 }, { 0, 1 }, G.col(1, 1, 1, a));
        end
        if lit then
            local t = now % 2.8;                                     -- (the coins glint, one after the other, every 2.8 s)
            for i, e in ipairs(G.EYES) do
                local p = at(e[1] * hw * 2 - hw, e[2] * hh * 2 - hh);
                G.glint(dl, p[1], p[2], e[3] * hw * 2, t - (i - 1) * 0.18);
            end
        end
        if imgui.IsItemClicked(1) then                               -- (right click: the settings panel, or closed again)
            G.panel = not G.panel;
        end
        if hov and not act and not G.panel then G.tip(dl, sw, sh); end
        dl:PopClipRect();
    end
    imgui.End();
    imgui.PopStyleVar(2);
    if G.panel then G.panel_draw(sw, sh, w, h); end
end

-- The look shared by the tooltip and the panel: YunaUI's - warm dark glass, a fine gold edge, glass pills - and its fonts
-- (Bahnschrift for the title, Segoe UI Semibold / Segoe UI for the rest)
G.GOLD, G.GOLD2, G.CREAM, G.MUTED = { 0.95, 0.76, 0.36 }, { 1.00, 0.88, 0.58 }, { 0.97, 0.94, 0.88 }, { 0.72, 0.68, 0.60 };
G.MODECOL = { lot = { 0.97, 0.78, 0.34 }, pass = { 0.93, 0.36, 0.32 }, off = { 0.70, 0.70, 0.72 } };
G.MODETXT = { lot = 'Auto lot ON', pass = 'Auto pass ON', off = 'Off' };
G.F = {};
function G.load_fonts()
    local dir = (os.getenv('WINDIR') or 'C:\\Windows') .. '\\Fonts\\';
    local function add(name, size)
        local f = io.open(dir .. name, 'rb');
        if f == nil then return nil; end
        f:close();
        local ok, font = pcall(imgui.AddFontFromFileTTF, dir .. name, size);
        return (ok and font) or nil;
    end
    G.F.title = { add('bahnschrift.ttf', 21) or add('seguisb.ttf', 20), 21 };
    G.F.semi = { add('seguisb.ttf', 16) or add('segoeui.ttf', 16), 16 };
    G.F.body = { add('segoeui.ttf', 15), 15 };
    G.F.small = { add('seguisb.ttf', 12) or add('segoeui.ttf', 12), 12 };
end
function G.push(k)                                                   -- (a font on; false if it isn't there - the game's font stays)
    local f = G.F[k];
    if not f or not f[1] then return false; end
    local newer = false;
    pcall(function() newer = f[1].LegacySize ~= nil; end);
    if newer then return (pcall(imgui.PushFont, f[1], f[2])); end
    return (pcall(imgui.PushFont, f[1]));
end
function G.unpush(on) if on then pcall(imgui.PopFont); end end
function G.c(t, a) return G.col(t[1], t[2], t[3], a or 1); end
function G.tw(s) local a, b = imgui.CalcTextSize(s); if type(a) == 'table' then return a.x, a.y; end return a, b; end
function G.text(dl, x, y, s, col) dl:AddText({ x + 1, y + 1 }, G.col(0, 0, 0, 0.55), s); dl:AddText({ x, y }, col, s); end
function G.say(dl, k, x, y, s, col)                                  -- (text in one of the fonts; gives its width and height)
    local on = G.push(k);
    local w, h = G.tw(s);
    G.text(dl, x, y, s, col);
    G.unpush(on);
    return w, h;
end
function G.size(k, s) local on = G.push(k); local w, h = G.tw(s); G.unpush(on); return w, h; end
function G.caps(dl, x, y, s, col)                                    -- (a small spaced-out label: MODE, ICON SIZE)
    local on = G.push('small');
    local cx = x;
    for ch in s:gmatch('.') do G.text(dl, cx, y, ch, col); cx = cx + G.tw(ch) + 1.6; end
    G.unpush(on);
end
-- Glass: a soft shadow, a see-through warm dark body that's lighter at the top, a bright line along the top edge,
-- a fine gold edge with a faint light one inside it
function G.glass(dl, x1, y1, x2, y2, R)
    R = R or 12;
    for i = 1, 6 do dl:AddRectFilled({ x1 - i + 2, y1 + i * 1.2 }, { x2 + i - 2, y2 + i * 1.8 }, G.col(0, 0, 0, 0.055), R + i); end
    dl:AddRectFilled({ x1, y1 }, { x2, y2 }, G.col(0.055, 0.048, 0.042, 0.78), R);
    local hh = (y2 - y1);
    for i = 0, 5 do                                                  -- (lighter towards the top, as light through glass)
        local t = i / 6;
        dl:AddRectFilled({ x1 + 1, y1 + 1 }, { x2 - 1, y1 + hh * (0.62 - t * 0.5) }, G.col(1, 0.92, 0.78, 0.018), R - 1);
    end
    dl:AddLine({ x1 + R, y1 + 1 }, { x2 - R, y1 + 1 }, G.col(1, 0.97, 0.88, 0.32), 1);
    dl:AddRect({ x1 - 1, y1 - 1 }, { x2 + 1, y2 + 1 }, G.col(0, 0, 0, 0.45), R + 1, 15, 1);
    dl:AddRect({ x1, y1 }, { x2, y2 }, G.c(G.GOLD, 0.50), R, 15, 1.2);
    dl:AddRect({ x1 + 1.5, y1 + 1.5 }, { x2 - 1.5, y2 - 1.5 }, G.col(1, 1, 1, 0.05), R - 1.5, 15, 1);
end
function G.rule(dl, x1, x2, y)                                       -- (a gold line that fades out at both ends)
    local m = (x1 + x2) / 2;
    dl:AddRectFilledMultiColor({ x1, y }, { m, y + 1 }, G.c(G.GOLD, 0), G.c(G.GOLD, 0.55), G.c(G.GOLD, 0.55), G.c(G.GOLD, 0));
    dl:AddRectFilledMultiColor({ m, y }, { x2, y + 1 }, G.c(G.GOLD, 0.55), G.c(G.GOLD, 0), G.c(G.GOLD, 0), G.c(G.GOLD, 0.55));
end
-- The tooltip: YunaLoot and what's on, then what the mouse does
function G.tip(dl, sw, sh)
    local mx, my = imgui.GetMousePos();
    if type(mx) == 'table' then mx, my = mx.x, mx.y; end
    local st = G.MODETXT[Y.mode] or 'Off';
    local rows = { { 'Click', 'change mode' }, { 'Drag', 'move' }, { 'Right click', 'settings' } };
    local tw_, th_ = G.size('title', 'YunaLoot');
    local sw_ = G.size('semi', st);
    local lw, rw, lh = 0, 0, 0;
    for _, r in ipairs(rows) do
        local a, h_ = G.size('semi', r[1]); local b = G.size('body', r[2]);
        lw, rw, lh = math.max(lw, a), math.max(rw, b), math.max(lh, h_);
    end
    local W = math.max(tw_ + 14 + sw_, lw + 14 + rw) + 32;
    local H = 12 + th_ + 12 + #rows * (lh + 4) + 10;
    local x, y = mx + 20, my + 22;
    if x + W > sw - 4 then x = mx - W - 12; end
    if y + H > sh - 4 then y = my - H - 12; end
    G.glass(dl, x, y, x + W, y + H, 11);
    G.say(dl, 'title', x + 16, y + 11, 'YunaLoot', G.c(G.GOLD2));
    local dot = G.MODECOL[Y.mode] or G.MUTED;                          -- (what's on: a lit dot and its name)
    local _, sh_ = G.size('semi', st);
    local dx, dy = x + W - 16 - sw_ - 12, y + 11 + th_ / 2;
    dl:AddCircleFilled({ dx, dy }, 6, G.c(dot, 0.25), 16);
    dl:AddCircleFilled({ dx, dy }, 3.5, G.c(dot), 16);
    G.say(dl, 'semi', x + W - 16 - sw_, y + 11 + (th_ - sh_) / 2, st, G.c(dot));
    G.rule(dl, x + 12, x + W - 12, y + 12 + th_ + 5);
    local ry = y + 12 + th_ + 12;
    for _, r in ipairs(rows) do
        G.say(dl, 'semi', x + 16, ry, r[1], G.c(G.CREAM));
        G.say(dl, 'body', x + 16 + lw + 14, ry + 1, r[2], G.c(G.MUTED));
        ry = ry + lh + 4;
    end
end
-- A glass pill button. pick: its colour when it's the one picked (nil: plain)
function G.pill(dl, id, x, y, w, h, label, pick)
    imgui.SetCursorScreenPos({ x, y });
    imgui.InvisibleButton(id, { w, h });
    local hov, clk = imgui.IsItemHovered(), imgui.IsItemClicked(0);
    local r = h / 2;
    if pick then
        dl:AddRectFilled({ x, y + 2 }, { x + w, y + h + 2 }, G.c(pick, 0.18), r);   -- (its light under it)
        dl:AddRectFilled({ x, y }, { x + w, y + h }, G.c(pick, hov and 1 or 0.92), r);
        dl:AddRectFilled({ x + 2, y + 1 }, { x + w - 2, y + h * 0.5 }, G.col(1, 1, 1, 0.22), r - 1);
        dl:AddRect({ x, y }, { x + w, y + h }, G.col(1, 1, 1, 0.35), r, 15, 1);
    else
        dl:AddRectFilled({ x, y }, { x + w, y + h }, G.col(1, 1, 1, hov and 0.09 or 0.045), r);
        dl:AddRectFilled({ x + 2, y + 1 }, { x + w - 2, y + h * 0.5 }, G.col(1, 1, 1, hov and 0.06 or 0.03), r - 1);
        dl:AddRect({ x, y }, { x + w, y + h }, G.col(1, 1, 1, hov and 0.24 or 0.12), r, 15, 1);
    end
    local on = G.push('semi');
    local tw, th = G.tw(label);
    local tc = pick and G.col(0.12, 0.08, 0.04, 1) or G.c(hov and G.CREAM or G.MUTED);
    dl:AddText({ x + (w - tw) / 2, y + (h - th) / 2 }, tc, label);
    G.unpush(on);
    return clk;
end
-- The settings panel (right click the goblin): which mode, the goblin's size, its place back to start
function G.panel_draw(sw, sh, gw, gh)
    local cfg = G.cfg;
    local tw_, th_ = G.size('title', 'YunaLoot');
    local _, lh = G.size('semi', 'Ag');
    local _, ch = G.size('small', 'MODE');
    local bw = math.max(G.size('semi', 'Off'), G.size('semi', 'Auto lot'), G.size('semi', 'Auto pass')) + 30;
    local P = 18;
    local PW = math.max(2 * P + 3 * bw + 16, tw_ + 140);
    local PH = P + th_ + 14 + ch + 8 + (lh + 12) + 18 + ch + 8 + 22 + 18 + (lh + 8) + P;
    local px = cfg.x + gw + 14;
    if px + PW > sw - 6 then px = cfg.x - PW - 14; end
    local py = math.max(6, math.min(sh - PH - 6, cfg.y + gh / 2 - PH / 2));
    imgui.SetNextWindowPos({ px - 8, py - 8 }, ImGuiCond_Always);
    imgui.SetNextWindowSize({ PW + 16, PH + 20 }, ImGuiCond_Always);
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, { 0, 0 });
    imgui.PushStyleVar(ImGuiStyleVar_WindowBorderSize, 0);
    local flags = bit.bor(ImGuiWindowFlags_NoDecoration, ImGuiWindowFlags_NoBackground, ImGuiWindowFlags_NoSavedSettings,
        ImGuiWindowFlags_NoMove, ImGuiWindowFlags_NoNav);
    if imgui.Begin('##yunaloot_panel', true, flags) then
        local dl = imgui.GetWindowDrawList();
        local x, y = px, py;
        G.glass(dl, x, y, x + PW, y + PH, 14);
        G.say(dl, 'title', x + P, y + P - 2, 'YunaLoot', G.c(G.GOLD2));
        local _, sh2 = G.size('body', 'settings');
        G.say(dl, 'body', x + P + tw_ + 10, y + P - 2 + (th_ - sh2) / 2 + 1, 'settings', G.c(G.MUTED));
        imgui.SetCursorScreenPos({ x + PW - 36, y + 10 });            -- (close: a small x in a glass circle)
        imgui.InvisibleButton('##yl_close', { 26, 26 });
        local chv = imgui.IsItemHovered();
        if imgui.IsItemClicked(0) then G.panel = false; end
        local qx, qy, qr = x + PW - 23, y + 23, 4.2;
        dl:AddCircleFilled({ qx, qy }, 11, G.col(1, 1, 1, chv and 0.10 or 0.04), 20);
        dl:AddCircle({ qx, qy }, 11, G.col(1, 1, 1, chv and 0.22 or 0.10), 20, 1);
        dl:AddLine({ qx - qr, qy - qr }, { qx + qr, qy + qr }, G.c(chv and G.CREAM or G.MUTED), 1.6);
        dl:AddLine({ qx - qr, qy + qr }, { qx + qr, qy - qr }, G.c(chv and G.CREAM or G.MUTED), 1.6);
        local ly = y + P + th_ + 6;
        G.rule(dl, x + 12, x + PW - 12, ly);
        -- MODE
        local my_ = ly + 14;
        G.caps(dl, x + P, my_, 'MODE', G.c(G.GOLD, 0.85));
        bw = (PW - 2 * P - 16) / 3;
        local by = my_ + ch + 8;
        for i, m in ipairs({ { 'off', 'Off' }, { 'lot', 'Auto lot' }, { 'pass', 'Auto pass' } }) do
            if G.pill(dl, '##yl_m' .. m[1], x + P + (i - 1) * (bw + 8), by, bw, lh + 12, m[2], (Y.mode == m[1]) and G.MODECOL[m[1]] or nil) and Y.mode ~= m[1] then
                G.set(m[1]);
            end
        end
        -- ICON SIZE: a slider in the same glass
        local sy = by + lh + 12 + 18;
        local size = math.max(40, math.min(200, tonumber(cfg.size) or 96));
        G.caps(dl, x + P, sy, 'ICON SIZE', G.c(G.GOLD, 0.85));
        local vs = size .. ' px';
        local vw = G.size('semi', vs);
        G.say(dl, 'semi', x + PW - P - vw, sy - 3, vs, G.c(G.CREAM));
        local tx1, tx2, ty = x + P + 6, x + PW - P - 6, sy + ch + 8 + 11;
        imgui.SetCursorScreenPos({ tx1 - 10, ty - 12 });
        imgui.InvisibleButton('##yl_size', { tx2 - tx1 + 20, 24 });
        local sh_, sa_ = imgui.IsItemHovered(), imgui.IsItemActive();
        if sa_ then
            local mx = imgui.GetMousePos();
            if type(mx) == 'table' then mx = mx.x; end
            cfg.size = math.floor(40 + math.max(0, math.min(1, (mx - tx1) / (tx2 - tx1))) * 160 + 0.5);
            size = cfg.size;
        end
        if imgui.IsItemDeactivated() then settings.save(); end
        local kx = tx1 + (size - 40) / 160 * (tx2 - tx1);
        dl:AddRectFilled({ tx1 - 3, ty - 4 }, { tx2 + 3, ty + 4 }, G.col(0, 0, 0, 0.45), 4);   -- (an inset glass track)
        dl:AddRect({ tx1 - 3, ty - 4 }, { tx2 + 3, ty + 4 }, G.col(1, 1, 1, 0.08), 4, 15, 1);
        dl:AddRectFilledMultiColor({ tx1, ty - 2 }, { kx, ty + 2 }, G.c(G.GOLD, 0.55), G.c(G.GOLD2, 1), G.c(G.GOLD2, 1), G.c(G.GOLD, 0.55));
        local kr = (sh_ or sa_) and 9 or 8;
        dl:AddCircleFilled({ kx, ty + 1.5 }, kr + 1, G.col(0, 0, 0, 0.35), 24);
        dl:AddCircleFilled({ kx, ty }, kr, G.c(G.GOLD), 24);
        dl:AddCircleFilled({ kx - kr * 0.25, ty - kr * 0.3 }, kr * 0.5, G.col(1, 1, 1, 0.35), 16);
        dl:AddCircle({ kx, ty }, kr, G.col(0.30, 0.19, 0.06, 0.9), 24, 1.4);
        -- its place back to the start
        local rw = G.size('semi', 'Reset place') + 32;
        if G.pill(dl, '##yl_reset', x + P, ty + 18, rw, lh + 8, 'Reset place') then
            cfg.x, cfg.y = -1, -1;
            settings.save();
        end
    end
    imgui.End();
    imgui.PopStyleVar(2);
end

ashita.events.register('load', 'yunaloot_load', function() pcall(G.load_fonts); end);

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
    elseif sub == 'settings' then                                    -- (/yloot settings: the panel, as a right click on the goblin)
        G.panel = not G.panel;
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
