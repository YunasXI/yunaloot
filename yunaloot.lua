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

ashita.events.register('d3d_present', 'yunaloot_tick', function() pcall(Y.tick); end);

ashita.events.register('packet_out', 'yunaloot_out', function(e)
    if e.id == 0x041 or e.id == 0x042 then pcall(Y.on_out, e); end
end);

ashita.events.register('command', 'yunaloot_cmd', function(e)
    local args = e.command:args();
    if #args == 0 or args[1]:lower() ~= '/yloot' then return; end
    e.blocked = true;
    local sub = (args[2] or ''):lower();
    if sub == 'lot' or sub == 'pass' or sub == 'off' then
        Y.mode = sub;
        if sub ~= 'off' then Y.done = {}; end                        -- (items already in the pool count from now)
        msg(({ lot = 'Auto lot: ON', pass = 'Auto pass: ON', off = 'Auto lot / pass: OFF' })[sub]);
    elseif sub == '' then
        msg(({ lot = 'Auto lot: ON', pass = 'Auto pass: ON', off = 'Auto lot / pass: OFF' })[Y.mode] .. '  (/yloot lot, /yloot pass, /yloot off)');
    else
        msg('/yloot lot, /yloot pass or /yloot off');
    end
end);

YUNALOOT_TEST = Y;                                                   -- (for the safe test: tools\menu-test\yunaloot_test.lua)
