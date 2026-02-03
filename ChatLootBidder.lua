local ChatLootBidder = ChatLootBidderFrame
--if ChatLootBidder == nil then print("XML Error"); return end
local T = ChatLootBidder_i18n
local startSessionButton = getglobal(ChatLootBidder:GetName() .. "StartSession")
local endSessionButton = getglobal(ChatLootBidder:GetName() .. "EndSession")
local clearSessionButton = getglobal(ChatLootBidder:GetName() .. "ClearSession")

local gfind = string.gmatch or string.gfind
math.randomseed(time() * 100000000000)
for i=1,3 do
  math.random(10000, 65000)
end

local function Roll()
  return math.random(1, 100)
end

local addonName = "ChatLootBidder"
local addonTitle = GetAddOnMetadata(addonName, "Title")
local addonNotes = GetAddOnMetadata(addonName, "Notes")
local addonVersion = GetAddOnMetadata(addonName, "Version")
local addonAuthor = GetAddOnMetadata(addonName, "Author")
local chatPrefix = "<CL> "
local me = UnitName("player")
-- Roll tracking heavily borrowed from RollTracker: http://www.wowace.com/projects/rolltracker/
if GetLocale() == 'deDE' then RANDOM_ROLL_RESULT = "%s w\195\188rfelt. Ergebnis: %d (%d-%d)"
elseif RANDOM_ROLL_RESULT == nil then RANDOM_ROLL_RESULT = "%s rolls %d (%d-%d)" end -- Using english language https://vanilla-wow-archive.fandom.com/wiki/WoW_constants if not set
local rollRegex = string.gsub(string.gsub(string.gsub("%s rolls %d (%d-%d)", "([%(%)%-])", "%%%1"), "%%s", "%(.+%)"), "%%d", "%(%%d+%)")

ChatLootBidder_ChatFrame_OnEvent = ChatFrame_OnEvent

local softReserveSessionName = nil
local softReservesLocked = false
local session = nil
local sessionMode = nil
local stage = {}
local lastWhisper = nil
local bossName = nil
local bosses = {
	["Highlord Mograine"] = "The Four Horsemen",
	["Thane Korth'azz"] = "The Four Horsemen",
	["Sir Zeliek"] = "The Four Horsemen",
	["Lady Blaumeux"] = "The Four Horsemen",
	["Princess Yauj"] = "Bug Trio",
	["Vem"] = "Bug Trio",
	["Lord Kri"] = "Bug Trio",
	["Emperor Vek'lor"] = "Twin Emperors",
	["Emperor Vek'nilash"] = "Twin Emperors",
}

local function DefaultFalse(prop) return prop == true end
local function DefaultTrue(prop) return prop == nil or DefaultFalse(prop) end

local function LoadVariables()
  ChatLootBidder_Store = ChatLootBidder_Store or {}
  ChatLootBidder_LootHistory = ChatLootBidder_LootHistory or {}
  ChatLootBidder_Store.ItemValidation = DefaultTrue(ChatLootBidder_Store.ItemValidation)
  ChatLootBidder_Store.RollAnnounce = DefaultTrue(ChatLootBidder_Store.RollAnnounce)
  ChatLootBidder_Store.AutoStage = DefaultTrue(ChatLootBidder_Store.AutoStage)
  ChatLootBidder_Store.BidAnnounce = DefaultFalse(ChatLootBidder_Store.BidAnnounce)
  ChatLootBidder_Store.BidSummary = DefaultFalse(ChatLootBidder_Store.BidSummary)
  ChatLootBidder_Store.BidChannel = ChatLootBidder_Store.BidChannel or "OFFICER"
  ChatLootBidder_Store.SessionAnnounceChannel = ChatLootBidder_Store.SessionAnnounceChannel or "RAID"
  ChatLootBidder_Store.WinnerAnnounceChannel = ChatLootBidder_Store.WinnerAnnounceChannel or "RAID_WARNING"
  ChatLootBidder_Store.DebugLevel = ChatLootBidder_Store.DebugLevel or 0
  ChatLootBidder_Store.TimerSeconds = ChatLootBidder_Store.TimerSeconds or 30
  ChatLootBidder_Store.MaxBid = ChatLootBidder_Store.MaxBid or 5000
  ChatLootBidder_Store.MinBid = ChatLootBidder_Store.MinBid or 1
  ChatLootBidder_Store.AltPenalty = ChatLootBidder_Store.AltPenalty or 0
  ChatLootBidder_Store.MaxOsBid = ChatLootBidder_Store.MaxOsBid or 50
  ChatLootBidder_Store.MaxTwinkBid = ChatLootBidder_Store.MaxTwinkBid or 30
  ChatLootBidder_Store.MinRarity = ChatLootBidder_Store.MinRarity or 4
  ChatLootBidder_Store.MaxRarity = ChatLootBidder_Store.MaxRarity or 5
  ChatLootBidder_Store.DefaultSessionMode = ChatLootBidder_Store.DefaultSessionMode or "MSOS" -- DKP | MSOS
  ChatLootBidder_Store.BreakTies = DefaultTrue(ChatLootBidder_Store.BreakTies)
  ChatLootBidder_Store.AddonVersion = addonVersion
  ChatLootBidder_Store.SoftReserveSessions = ChatLootBidder_Store.SoftReserveSessions or {}
  ChatLootBidder_Store.AutoRemoveSrAfterWin = DefaultTrue(ChatLootBidder_Store.AutoRemoveSrAfterWin)
  ChatLootBidder_Store.AutoLockSoftReserve = DefaultTrue(ChatLootBidder_Store.AutoLockSoftReserve)
  ChatLootBidder_Store.ListenLootHistory = DefaultFalse(ChatLootBidder_Store.ListenLootHistory)
  -- TODO: Make this custom per Soft Reserve session and make this the default when a new list is started
  ChatLootBidder_Store.DefaultMaxSoftReserves = 1
end

local function NormalizeKeyword(raw)
  if not raw then return nil end

  local t = string.lower(raw)

  if string.find(t, "ms") then
    return "ms"
  end

  if string.find(t, "os") then
    return "os"
  end

  if string.find(t, "twink") then
    return "twink"
  end

  if string.find(t, "roll") then
    return "roll"
  end

  if string.find(t, "cancel") then
    return "cancel"
  end

  if string.find(t, "sr") then
    return "sr"
  end

  if string.find(t, "real") then
    return "real"
  end

  if string.find(t, "notes") then
    return "notes"
  end

  return raw
end

local function Trim(str)
  local _start, _end, _match = string.find(str, '^%s*(.-)%s*$')
  return _match or ""
end

local function ToWholeNumber(numberString, default)
  if default == nil then default = 0 end
  if numberString == nil then return default end
  local num = math.floor(tonumber(numberString) or default)
  if default == num then return default end
  return math.max(num, default)
end

local function Error(message)
	DEFAULT_CHAT_FRAME:AddMessage("|cffbe5eff" .. chatPrefix .. "|cffff0000 "..message)
end

local function Message(message)
	DEFAULT_CHAT_FRAME:AddMessage("|cffbe5eff".. chatPrefix .."|r "..message)
end

local function Debug(message)
	if ChatLootBidder_Store.DebugLevel > 0 then
		DEFAULT_CHAT_FRAME:AddMessage("|cffbe5eff".. chatPrefix .."|cffffff00 "..message)
	end
end

local function Trace(message)
	if ChatLootBidder_Store.DebugLevel > 1 then
		DEFAULT_CHAT_FRAME:AddMessage("|cffbe5eff".. chatPrefix .."|cffffff00 "..message)
	end
end

function ChatLootBidder:SetPropValue(propName, propValue, prefix)
  if prefix then
    propName = string.sub(propName, strlen(prefix)+1)
  end
  if ChatLootBidder_Store[propName] ~= nil then
    ChatLootBidder_Store[propName] = propValue
    local v = propValue
    if type(v) == "boolean" then
      v = v and "on" or "off"
    end
    Debug((T[propName] or propName) .. " is " .. tostring(v))

    -- Special Handlers for specific properties here
    if propName == "DefaultSessionMode" then
      ChatLootBidder:RedrawStage()
    end

  else
    Error(propName .. " is not initialized")
  end
end

local ShowHelp = function()
	Message("/loot - Open GUI Options")
	Message("/loot stage [itm1] [itm2] - Stage item(s) for a future session start")
	Message("/loot start [itm1] [itm2] [#timer_optional] - Start a session for item(s) + staged items(s)")
	Message("/loot end - End a loot session and announce winner(s)")
	Message("/loot sr load [name]  - Load a SR list (by name, optional)")
	Message("/loot dkp - Send options and current dkp for raid members")
	Message(addonNotes .. " for detailed instructions, bugs, and suggestions")
	Message("Written by " .. addonAuthor)
end

local function GetRaidIndex(unitName)
  if UnitInRaid("player") == 1 then
     for i = 1, GetNumRaidMembers() do
        if UnitName("raid"..i) == unitName then
           return i
        end
     end
  end
  return 0
end

local function IsInRaid(unitName)
  return GetRaidIndex(unitName) ~= 0
end

local function IsRaidAssistant(unitName)
  _, rank = GetRaidRosterInfo(GetRaidIndex(unitName));
  return rank ~= 0
end

local function GetPlayerClass(unitName)
  _, _, _, _, _, playerClass = GetRaidRosterInfo(GetRaidIndex(unitName));
  return playerClass
end

local function IsMasterLooterSet()
  local method, _ = GetLootMethod()
  return method == "master"
end

local function IsStaticChannel(channel)
  channel = channel == nil and nil or string.upper(channel)
  return channel == "RAID" or channel == "RAID_WARNING" or channel == "SAY" or channel == "EMOTE" or channel == "PARTY" or channel == "GUILD" or channel == "OFFICER" or channel == "YELL"
end

local function IsTableEmpty(tbl)
  if tbl == nil then return true end
  local next = next
  return next(tbl) == nil
end

local function FlattenLootHistory(history)
    if history == nil then return {} end
    local flattened = {}
    
    for _, record in ipairs(history) do
        table.insert(flattened, {
            record.character or "",
            record.item or "",
            record.bid_type or "",
            record.bid_amount or "",
            record.boss or "",
            record.datetime or ""
        })
    end
    
    return flattened
end

local function UnflattenLootHistory(csvData)
    local history = {}
    
    local fieldIndices = {}
    local hasHeader = false
    
    if getn(csvData) > 0 then
        local header = csvData[1]
        if header[1] == "character" and header[2] == "item" then
            hasHeader = true
            for i, field in ipairs(header) do
                fieldIndices[field] = i
            end
        else
            fieldIndices = {
                character = 1,
                item = 2,
                bid_type = 3,
                bid_amount = 4,
                boss = 5,
                datetime = 6
            }
        end
    end
    
    local startRow = hasHeader and 2 or 1
    for i = startRow, getn(csvData) do
        local row = csvData[i]
        local record = {
            character = row[fieldIndices.character or 1],
            item = row[fieldIndices.item or 2],
            bid_type = row[fieldIndices.bid_type or 3],
            bid_amount = tonumber(row[fieldIndices.bid_amount or 4]) or nil,
            boss = row[fieldIndices.boss or 5] ~= "" and row[fieldIndices.boss or 5] or nil,
            datetime = row[fieldIndices.datetime or 6]
        }
        table.insert(history, record)
    end
    
    return history
end

-- Flatten a Player: [ SR1, SR2 ] structure into: { [Player, SR1], [Player, SR2] }
local function Flatten(tbl)
  if tbl == nil then return {} end
  local flattened = {}
  local k, arr, v
  for k, arr in pairs(tbl) do
    for _,v in pairs(arr) do
      table.insert(flattened, { k, v })
    end
  end
  return flattened
end

-- Take a [[Player, SR1], [Player, SR2]] data structure and Map it: { Player: [ SR1, SR2 ] }
local function UnFlatten(tbl)
  if tbl == nil then return {} end
  local unflattened = {}
  local arr
  for _, arr in pairs(tbl) do
    if unflattened[arr[1]] == nil then unflattened[arr[1]] = {} end
    if arr[2] ~= nil then
      table.insert(unflattened[Trim(arr[1])], Trim(arr[2]))
    end
  end
  return unflattened
end

local function TableContains(table, element)
  local value
  for _,value in pairs(table) do
    if value == element then
      return true
    end
  end
  return false
end

local function ParseItemNameFromItemLink(i)
  local _, _ , n = string.find(i, "|h.(.-)]")
  return n
end

local function TableLength(tbl)
  if tbl == nil then return 0 end
  local count = 0
  for _ in pairs(tbl) do count = count + 1 end
  return count
end

local function SplitBySpace(str)
  local commandlist = { }
  local command
  for command in gfind(str, "[^ ]+") do
    table.insert(commandlist, command)
  end
  return commandlist
end

local function GetKeysWhere(tbl, fn)
  if tbl == nil then return {} end
  local keys = {}
  for key,value in pairs(tbl) do
    if fn == nil or fn(key, value) then
      table.insert(keys, key)
    end
  end
  return keys
end

local function GetKeys(tbl)
  return GetKeysWhere(tbl)
end

local function GetKeysSortedByValue(tbl)
  local keys = GetKeys(tbl)
  table.sort(keys, function(a, b)
    return tbl[a] > tbl[b]
  end)
  return keys
end

local function SendToChatChannel(channel, message, prio)
  if IsStaticChannel(channel) then
    ChatThrottleLib:SendChatMessage(prio or "NORMAL", shortName, message, channel)
  else
    local channelIndex = GetChannelName(channel)
    if channelIndex > 0 then
      ChatThrottleLib:SendChatMessage(prio or "NORMAL", shortName, message, "CHANNEL", nil, channelIndex)
    else
      Error(channel .. " <Not In Channel> " .. message)
    end
  end
end

local function MessageBidSummaryChannel(message, force)
  if ChatLootBidder_Store.BidSummary or force then
    SendToChatChannel(ChatLootBidder_Store.BidChannel, message)
    Trace("<SUMMARY>" .. message)
  else
    Debug("<SUMMARY>" .. message)
  end
end

local function MessageBidChannel(message)
  if ChatLootBidder_Store.BidAnnounce then
    SendToChatChannel(ChatLootBidder_Store.BidChannel, message)
    Trace("<BID>" .. message)
  else
    Debug("<BID>" .. message)
  end
end

local function MessageWinnerChannel(message)
  SendToChatChannel(ChatLootBidder_Store.WinnerAnnounceChannel, message)
  Trace("<WIN>" .. message)
end

local function MessageStartChannel(message)
  if IsInRaid(me) then
    SendToChatChannel(ChatLootBidder_Store.SessionAnnounceChannel, message)
  else
    Message(message)
  end
  Trace("<START>" .. message)
end

local function SendResponse(message, bidder)
  if bidder == me then
    Message(message)
  else
    ChatThrottleLib:SendChatMessage("ALERT", shortName, message, "WHISPER", nil, bidder)
  end
end

local function AppendNote(note)
  return (note == nil or note == "") and "" or " [ " .. note .. " ]"
end

local function PlayerWithClassColor(unit)
  -- if RAID_CLASS_COLORS and pfUI then -- pfUI loads class colors
  if RAID_CLASS_COLORS then
    local unitClass = GetPlayerClass(unit)
    local colorStr = RAID_CLASS_COLORS[unitClass].colorStr
    if colorStr and string.len(colorStr) == 8 then
      return "\124c" .. colorStr .. "\124Hplayer:" .. unit .. "\124h" .. unit .. "\124h\124r"
    end
  end
  return unit
end

local function Srs(n)
  local n = n or softReserveSessionName
  local srs = ChatLootBidder_Store.SoftReserveSessions[n]
  if srs ~= nil then return srs end
  ChatLootBidder_Store.SoftReserveSessions[n] = {}
  return ChatLootBidder_Store.SoftReserveSessions[n];
end

function ChatLootBidder:LoadedSoftReserveSession()
  if softReserveSessionName then
    return unpack({softReserveSessionName, ChatLootBidder_Store.SoftReserveSessions[softReserveSessionName]})
  end
  return unpack({nil, nil})
end

local function HandleSrRemove(bidder, item)
  local itemName = ParseItemNameFromItemLink(item)
  if Srs()[bidder] == nil then
    Srs()[bidder] = {}
  end
  local sr = Srs()[bidder]
  local i, v
  for i,v in pairs(sr) do
    if v == itemName then
        table.remove(sr,i)
        SendResponse("You are no longer reserving: " .. itemName, bidder)
        return
    end
  end
end

local function realAmt(amt, real)
  if real ~= nil and amt ~= real then
    return amt .. "(" .. real .. ")"
  end
  return amt
end

local function AddToLootHistory(winner, item, bidType, bidAmount)
    -- Получаем текущую дату и время в формате HH:MM:SS DD/MM/YY
    local time = date("%H:%M:%S")
    local dateStr = date("%d/%m/%y")
    local datetime = time .. " " .. dateStr
    bossName = bossName or ""
    
    local record = {
        character = winner,
        item = ParseItemNameFromItemLink(item),
        bid_type = bidType,
        bid_amount = bidAmount or nil,
        boss = bossName,
        datetime = datetime
    }
    
    table.insert(ChatLootBidder_LootHistory, record)
	winnerAddonMessage = string.format("%s, %s, %s, %s, %s, %s", 
        record.character, record.item, record.bid_type, 
        record.bid_amount or "", record.boss, record.datetime)
	ChatThrottleLib:SendAddonMessage("BULK", "ChatLootBidder", winnerAddonMessage, "RAID")
	
    Debug(string.format("Added to loot history: "..winnerAddonMessage))
end

local function BidSummary(announceWinners)
    if session == nil then
        Error("There is no existing session")
        return
    end
    
    local summaries = {}
    for item,itemSession in pairs(session) do
        local sr = itemSession["sr"] or {}
        local ms = itemSession["ms"] or {}
        local ofs = itemSession["os"] or {}
        local twink = itemSession["twink"] or {}
        local roll = itemSession["roll"] or {}
        local cancel = itemSession["cancel"] or {}
        local notes = itemSession["notes"] or {}
        local real = itemSession["real"] or {}

        local allBids = {}
        
        for bidder,bid in pairs(ms) do
            if cancel[bidder] == nil then
                allBids[bidder] = {value = bid, tier = "ms", priority = 3, real = real[bidder]}
            end
        end
        
        for bidder,bid in pairs(ofs) do
            if cancel[bidder] == nil then
                allBids[bidder] = {value = bid, tier = "os", priority = 3, real = real[bidder]}
            end
        end
        
        for bidder,bid in pairs(twink) do
            if cancel[bidder] == nil then
                allBids[bidder] = {value = bid, tier = "twink", priority = 3, real = real[bidder]}
            end
        end
        
        if IsTableEmpty(ms) and IsTableEmpty(ofs) and IsTableEmpty(twink) then
            for bidder,bid in pairs(sr) do
                allBids[bidder] = {value = 1, tier = "sr", priority = 0}
            end
        end
        
        if IsTableEmpty(ms) and IsTableEmpty(ofs) and IsTableEmpty(twink) and IsTableEmpty(sr) then
            for bidder,bid in pairs(roll) do
                if cancel[bidder] == nil then
                    if bid == -1 then
                        bid = Roll()
                        roll[bidder] = bid
                        if ChatLootBidder_Store.RollAnnounce then
                            MessageStartChannel(PlayerWithClassColor(bidder) .. " rolls " .. bid .. " (1-100) for " .. item)
                        else
                            SendResponse("You roll " .. bid .. " (1-100) for " .. item, bidder)
                        end
                    end
                    allBids[bidder] = {value = bid, tier = "roll", priority = -1}
                end
            end
        end
        
        local sortedBidders = {}
        for bidder,_ in pairs(allBids) do
            table.insert(sortedBidders, bidder)
        end
        
        table.sort(sortedBidders, function(a,b)
            local bidA = allBids[a]
            local bidB = allBids[b]
            if bidA.priority ~= bidB.priority then
                return bidA.priority > bidB.priority
            end
            return bidA.value > bidB.value
        end)
        
        local winners = {}
        local winningBid = nil
        local winningTier = nil
        
        if getn(sortedBidders) > 0 then
            winningBid = allBids[sortedBidders[1]].value
            winningTier = allBids[sortedBidders[1]].tier

            for i = 1, getn(sortedBidders) do
                local bidder = sortedBidders[i]
                local bid = allBids[bidder]
                if bid.priority == allBids[sortedBidders[1]].priority and bid.value == winningBid then
                    table.insert(winners, bidder)
                else
                    break
                end
            end
        end
        
        local header = true
        local summary = {}
		local sortedMainspecKeys = GetKeysSortedByValue(ms)
		if not IsTableEmpty(ms) and header then 
			table.insert(summary, "- Main Spec:")
		end
		for _,bidder in ipairs(sortedMainspecKeys) do
			if cancel[bidder] == nil then
				local bid = ms[bidder]
				table.insert(summary, "-- " .. PlayerWithClassColor(bidder) .. ": " .. realAmt(bid, real[bidder]) .. AppendNote(notes[bidder]))
			end
		end
		if not IsTableEmpty(ofs) and header then 
			table.insert(summary, "- Off Spec:")
		end
		local sortedOffspecKeys = GetKeysSortedByValue(ofs)
		for _,bidder in ipairs(sortedOffspecKeys) do
			if cancel[bidder] == nil then
				local bid = ofs[bidder]
				table.insert(summary, "-- " .. PlayerWithClassColor(bidder) .. ": " .. realAmt(bid, real[bidder]) .. AppendNote(notes[bidder]))
			end
		end
        
		if not IsTableEmpty(twink) and header then 
			table.insert(summary, "- Twink:")
		end
		local sortedTwinkKeys = GetKeysSortedByValue(twink)
		for _,bidder in ipairs(sortedTwinkKeys) do
			if cancel[bidder] == nil then
				local bid = twink[bidder]
				table.insert(summary, "-- " .. PlayerWithClassColor(bidder) .. ": " .. realAmt(bid, real[bidder]) .. AppendNote(notes[bidder]))
			end
		end
        
		if not IsTableEmpty(sr) and header then 
			table.insert(summary, "- Soft Reserve:")
		end
        if not IsTableEmpty(sr) and IsTableEmpty(ms) and IsTableEmpty(ofs) and IsTableEmpty(twink) then
            local sortedSrKeys = GetKeysSortedByValue(sr)
            for _,bidder in ipairs(sortedSrKeys) do
                table.insert(summary, "-- " .. PlayerWithClassColor(bidder))
            end
        end
        
        if not IsTableEmpty(roll) and IsTableEmpty(ms) and IsTableEmpty(ofs) and IsTableEmpty(twink) and IsTableEmpty(sr) then
            local sortedRollKeys = GetKeysSortedByValue(roll)
			if header then 
				table.insert(summary, "- Rolls:")
			end
            for _,bidder in ipairs(sortedRollKeys) do
                if cancel[bidder] == nil then
                    local bid = roll[bidder]
                    table.insert(summary, "-- " .. PlayerWithClassColor(bidder) .. ": " .. bid .. AppendNote(notes[bidder]))
                end
            end
        end
        

        local breakTies = ChatLootBidder_Store.BreakTies or sessionMode ~= "DKP"
        if getn(winners) > 1 and breakTies then
            MessageWinnerChannel(table.concat(winners, ", ") .. " tied with " .. 
                              (winningTier == "roll" and "roll of " or (string.upper(winningTier) .. " bid of ")) .. 
                              winningBid .. ", rolling it off:")
            
            local newWinners = {}
            local winningRoll = 0
            
            for _, bidder in ipairs(winners) do
                local r = roll[bidder]
                if r == -1 or r == nil then
                    r = Roll()
                    roll[bidder] = r
                    MessageWinnerChannel(PlayerWithClassColor(bidder) .. " rolls " .. r .. " (1-100) for " .. item)
                else
                    MessageWinnerChannel(PlayerWithClassColor(bidder) .. " already rolled " .. r .. " (1-100) for " .. item)
                end
                
                if r > winningRoll then
                    winningRoll = r
                    newWinners = {bidder}
                elseif r == winningRoll then
                    table.insert(newWinners, bidder)
                end
            end
            
            winners = newWinners
            
            while getn(winners) > 1 do
                MessageWinnerChannel(table.concat(winners, ", ") .. " tied with roll of " .. winningRoll .. ", rolling again:")
                
                winningRoll = 0
                local tempWinners = {}
                
                for _, bidder in ipairs(winners) do
                    local r = Roll()
                    roll[bidder] = r
                    MessageWinnerChannel(PlayerWithClassColor(bidder) .. " rolls " .. r .. " (1-100) for " .. item)
                    
                    if r > winningRoll then
                        winningRoll = r
                        tempWinners = {bidder}
                    elseif r == winningRoll then
                        table.insert(tempWinners, bidder)
                    end
                end
                
                winners = tempWinners
            end
        end
        

        if getn(winners) == 0 then
            if announceWinners then MessageStartChannel("No bids received for " .. item) end
        elseif announceWinners then
            local winnerMessage
            if getn(winners) > 1 then
                winnerMessage = table.concat(winners, ", ") .. " tie for " .. item
            else
                winnerMessage = winners[1] .. " wins " .. item
            end
            
            if sessionMode == "DKP" then
                winnerMessage = winnerMessage .. " with " .. (winningTier == "roll" and "roll of " or (string.upper(winningTier) .. " bid of "))
                if getn(winners) == 1 and winningTier ~= "roll" then
                    winnerMessage = winnerMessage .. realAmt(winningBid, allBids[winners[1]].real)
                else
                    winnerMessage = winnerMessage .. winningBid
                end
                

                if winningTier ~= "roll" and winningTier ~= "sr" then
                    for _, winner in ipairs(winners) do
                        local dkpToDeduct = allBids[winner].real or winningBid
                        local currentDkp = ChatLootBidder:GetPlayerDkpFromGuildNotes(winner)
                        if currentDkp then
                            local newDkp = currentDkp - dkpToDeduct
                            ChatLootBidder:UpdatePlayerDkpInGuildNotes(winner, newDkp)
                            Debug(string.format("Deducted %d DKP from %s (new balance: %d)", 
                                dkpToDeduct, winner, newDkp))
                        else
                            Debug(string.format("Could not find DKP balance for %s", winner))
                        end
                    end
                end
            else
                winnerMessage = winnerMessage .. " (" .. string.upper(winningTier) .. ")"
            end
            
            MessageWinnerChannel(winnerMessage)
            
            for _, winner in ipairs(winners) do
                local bidType = (winningTier == "ms" or winningTier == "os" or winningTier == "twink") and "dkp" or winningTier
                local bidAmount = (bidType == "dkp") and winningBid or nil
                
                AddToLootHistory(winner, item, bidType, bidAmount)
            end
        end
        
        table.insert(summaries, summary)
        
        if winningTier == "sr" and ChatLootBidder_Store.AutoRemoveSrAfterWin and getn(winners) == 1 then
            HandleSrRemove(winners[1], item)
        end
    end
    
    for _, summary in ipairs(summaries) do
        for _, line in ipairs(summary) do
            MessageBidSummaryChannel(line)
        end
    end
end

function ChatLootBidder:End()
  ChatThrottleLib:SendAddonMessage("BULK", "NotChatLootBidder", "endSession=1", "RAID")
  BidSummary(true)
  session = nil
  sessionMode = nil
  -- stage = nil
  if getn(stage) > 0 then
  else
	 ChatLootBidder:Hide()
  end
  endSessionButton:Hide()
  ChatLootBidder:RedrawStage()
end

local function GetItemLinks(str)
  local itemLinks = {}
  local _start, _end, _lastEnd = nil, -1, -1
  while true do
    _start, _end = string.find(str, "|c.-|H.-|h|r", _end + 1)
    if _start == nil then
      return itemLinks, _lastEnd
    end
    _lastEnd = _end
    table.insert(itemLinks, string.sub(str, _start, _end))
  end
end

function ChatLootBidder:Start(items, minBid, mode)
    if not IsRaidAssistant(me) then 
        Error("You must be a raid leader or assistant in a raid to start a loot session") 
        return 
    end
    
    local mode = mode ~= nil and mode or ChatLootBidder_Store.DefaultSessionMode
    if session ~= nil then ChatLootBidder:End() end

    local currentItem = nil
    
	if getn(stage) == 0 then
		ChatLootBidder:SetHeight(100)
	end
    if items and getn(items) > 0 then
        currentItem = items[1]
        
        stage[currentItem] = nil
        
        for i = 2, getn(items) do
            stage[items[i]] = true
        end
    else
        for k, v in pairs(stage) do
            if v == true then
                currentItem = k
                stage[k] = nil
                break
            end
        end
    end
    
    if not currentItem then 
        Error("You must provide at least a single item to bid on") 
        return 
    end
    
    ChatLootBidder:RedrawStage()
    ChatLootBidder:EndSessionButtonShown()
    
    session = {}
    sessionMode = mode
    
    if ChatLootBidder_Store.AutoLockSoftReserve and softReserveSessionName ~= nil and not softReservesLocked then
        softReservesLocked = true
        MessageStartChannel("Soft Reserves for " .. softReserveSessionName .. " are now LOCKED")
    end
    
    local srs = mode == "MSOS" and softReserveSessionName ~= nil and ChatLootBidder_Store.SoftReserveSessions[softReserveSessionName] or {}
    local startChannelMessage = {
        "Bid on the following items",
        "-----------",
        currentItem
    }
    
    local minimumBid = (minBid ~= nil and tostring(minBid)) or tostring(ChatLootBidder_Store.MinBid)
    local bidAddonMessage = "mode="..mode..",minimumBid="..minimumBid..",MaxOsBid="..tostring(ChatLootBidder_Store.MaxOsBid)..",MaxTwinkBid="..tostring(ChatLootBidder_Store.MaxTwinkBid)..",items="..string.gsub(currentItem, ",", "~~~")
    
    local itemName = ParseItemNameFromItemLink(currentItem)
    local srsOnItem = GetKeysWhere(srs, function(player, playerSrs) return IsInRaid(player) and TableContains(playerSrs, itemName) end)
    local srLen = TableLength(srsOnItem)
    
    session[currentItem] = {
        cancel = {},
        roll = {},
        real = {},
        minBid = minimumBid,
        notes = {},
        ms = {},
        os = {},
        twink = {}
    }
    
    if srLen > 0 then
        startChannelMessage[3] = currentItem .. " SR (" .. srLen .. ")"
        session[currentItem].sr = {}
        
        for _, sr in pairs(srsOnItem) do
            session[currentItem].sr[sr] = 1
            session[currentItem].roll[sr] = -1
            if srLen > 1 then
                SendResponse("Your Soft Reserve for " .. currentItem .. " is contested by " .. (srLen-1) .. " other player" .. (srLen == 2 and "" or "s") .. ". '/random' now to record your own roll or do nothing for the addon to roll for you at the end of the session.", sr)
            else
                SendResponse("You won " .. currentItem .. " with your Soft Reserve!", srsOnItem[1])
            end
        end
    end
    
    table.insert(startChannelMessage, "-----------")
    table.insert(startChannelMessage, "/w " .. PlayerWithClassColor(me) .. " " .. currentItem .. " ms/os/twink/roll" .. (mode == "DKP" and " #bid (minBid: "..minimumBid..")" or "") .. " [optional-note]")
    
    for _, l in pairs(startChannelMessage) do
        MessageStartChannel(l)
    end
    
    timer = ChatLootBidder_Store.TimerSeconds
    if BigWigs and timer > 0 then BWCB(timer, "Bidding Ends") end
    
    ChatThrottleLib:SendAddonMessage("BULK", "NotChatLootBidder", bidAddonMessage, "RAID")
end

function ChatLootBidder:Clear(stageOnly)
  if session == nil or stageOnly then
    if IsTableEmpty(stage) then
      Message("There is no active session or stage")
    else
      stage = nil
      Message("Cleared the stage")
      ChatLootBidder:RedrawStage()
    end
  else
    session = nil
    Message("Cleared the current loot session")
  end
end

function ChatLootBidder:Unstage(item, redraw)
  stage[item] = false
  if redraw then ChatLootBidder:RedrawStage() end
end

function ChatLootBidder:HandleSrDelete(providedName)
  if softReserveSessionName == nil and providedName == nil then
    Error("No Soft Reserve session loaded or provided for deletion")
  elseif providedName == nil then
    ChatLootBidder_Store.SoftReserveSessions[softReserveSessionName] = nil
    Message("Deleted currently loaded Soft Reserve session: " .. softReserveSessionName)
    softReserveSessionName = nil
  elseif ChatLootBidder_Store.SoftReserveSessions[providedName] == nil then
    Error("No Soft Reserve session exists with the label: " .. providedName)
  else
    ChatLootBidder_Store.SoftReserveSessions[providedName] = nil
    Message("Deleted Soft Reserve session: " .. providedName)
  end
  if providedName == nil or providedName == softReserveSessionName then
    SrEditFrame:Hide()
  end
end

local function craftName(appender)
  return date("%y-%m-%d") .. (appender == 0 and "" or ("-"..appender))
end

function ChatLootBidder:HandleSrAddDefault()
  local appender = 0
  while ChatLootBidder_Store.SoftReserveSessions[craftName(appender)] ~= nil do
    appender = appender + 1
  end
  softReserveSessionName = craftName(appender)
  local srs = Srs()
  Message("New Soft Reserve list [" .. softReserveSessionName .. "] loaded")
  SrEditFrame:Hide()
  ChatLootBidderOptionsFrame_Init(softReserveSessionName)
end

function ChatLootBidder:HandleSrLoad(providedName)
  if providedName then
    softReserveSessionName = providedName
    local srs = Srs()
    ValidateFixAndWarn(srs)
    Message("Soft Reserve list [" .. softReserveSessionName .. "] loaded with " .. TableLength(srs) .. " players with soft reserves")
    SrEditFrame:Hide()
    ChatLootBidderOptionsFrame_Init(softReserveSessionName)
  else
    ChatLootBidder:HandleSrAddDefault()
  end
end

function ChatLootBidder:HandleSrUnload()
  if softReserveSessionName == nil then
    Error("No Soft Reserve session loaded")
  else
    Message("Unloaded Soft Reserve session: " .. softReserveSessionName)
    softReserveSessionName = nil
  end
  ChatLootBidderOptionsFrame_Reload()
  SrEditFrame:Hide()
end

function ChatLootBidder:HandleSrInstructions()
  MessageStartChannel("Set your SR: /w " .. PlayerWithClassColor(me) .. " sr [item-link or exact-item-name]")
  MessageStartChannel("Get your current SR: /w " .. PlayerWithClassColor(me) .. " sr")
  MessageStartChannel("Clear your current SR: /w " .. PlayerWithClassColor(me) .. " sr clear")
end

function ChatLootBidder:HandleSrShow()
  if softReserveSessionName == nil then
    Error("No Soft Reserve session loaded")
  else
    local srs = Srs()
    if IsTableEmpty(srs) then
      Error("No Soft Reserves placed yet")
      return
    end
    MessageStartChannel("Soft Reserve Bids:")
    local keys = GetKeys(srs)
    table.sort(keys)
    local player
    for _, player in pairs(keys) do
      local sr = srs[player]
      if not IsTableEmpty(sr) then
        local msg = PlayerWithClassColor(player) .. ": " .. table.concat(sr, ", ")
        if IsInRaid(player) then
          MessageStartChannel(msg)
        else
          Message(msg)
        end
      end
    end
  end
end

local function EncodeSemicolon()
  local encoded = ""
  for k,v in pairs(Srs()) do
    encoded = encoded .. k
    for _, sr in pairs(v) do
      encoded = encoded .. " ; " .. sr
    end
    encoded = encoded .. "\n"
  end
  return encoded
end

local function EncodeRaidResFly()
  local encoded = ""
  local flat = Flatten(Srs())
  for _,arr in flat do
    -- [00:00]Autozhot: Autozhot - Band of Accuria
    encoded = (encoded or "") .. "[00:00]"..arr[1]..": "..arr[1].." - "..arr[2].."\n"
  end
  return encoded
end

-- This is the most simple pretty print function possible applciable to { key : [value, value, value] } structures only
local function PrettyPrintJson(encoded)
  -- The default empty structure should be an object, not an array
  if encoded == "[]" then return "{}" end
  encoded = string.gsub(encoded, "{", "{\n")
  encoded = string.gsub(encoded, "}", "\n}")
  encoded = string.gsub(encoded, "],", "],\n")
  return encoded
end

local function HandleChannel(prop, channel)
  if IsStaticChannel(channel) then channel = string.upper(channel) end
  ChatLootBidder_Store[prop] = channel
  Message(T[prop] .. " announce channel set to " .. channel)
  getglobal("ChatLootBidderOptionsFrame" .. prop):SetValue(channel)
end

function ChatLootBidder:HandleEncoding(encodingType)
  if softReserveSessionName == nil then
    Error("No Soft Reserve list is loaded")
  else
    local encoded
    if encodingType == "csv" then
      encoded = csv:toCSV(Flatten(Srs()))
    elseif encodingType == "json" then
      encoded = PrettyPrintJson(json.encode(Srs()))
    elseif encodingType == "semicolon" then
      encoded = EncodeSemicolon()
    elseif encodingType == "raidresfly" then
      encoded = EncodeRaidResFly()
    end
    if not SrEditFrame:IsVisible() then
      SrEditFrame:Show()
    elseif SrEditFrameHeaderString:GetText() == encodingType then
      SrEditFrame:Hide()
    end
    SrEditFrameText:SetText(encoded)
    SrEditFrameHeaderString:SetText(encodingType)
  end
end

function ChatLootBidder:HandleShowLootHistory()
	local encoded = csv:toCSV(FlattenLootHistory(ChatLootBidder_LootHistory))
	if not SrEditFrame:IsVisible() then
	  SrEditFrame:Show()
	elseif SrEditFrameHeaderString:GetText() == 'LootHistory' then
	  SrEditFrame:Hide()
	end
	SrEditFrameText:SetText(encoded)
	SrEditFrameHeaderString:SetText('LootHistory')
end

function ChatLootBidder:HandleShowImportDKP()
	if not SrEditFrame:IsVisible() then
	  SrEditFrame:Show()
	elseif SrEditFrameHeaderString:GetText() == 'ImportDKP' then
	  SrEditFrame:Hide()
	end
	SrEditFrameText:SetText('')
	SrEditFrameHeaderString:SetText('ImportDKP')
end

function ChatLootBidder:HandleShowPlayers()
    local raidMembers = {}
    
    if IsInRaid(me) then
        for i = 1, GetNumRaidMembers() do
            local name, _, _, _, _, _, _, _, _, _, _ = GetRaidRosterInfo(i)
            if name then
                table.insert(raidMembers, name)
            end
        end
    else
        table.insert(raidMembers, UnitName("player"))
    end
    table.sort(raidMembers, function(a, b)
        return a < b
    end)
    
    local playerText = ""
    for i, name in ipairs(raidMembers) do
        playerText = playerText .. name .. "\n"
    end
    
    if not SrEditFrame:IsVisible() then
        SrEditFrame:Show()
    elseif SrEditFrameHeaderString:GetText() == 'Players' then
        SrEditFrame:Hide()
        return
    end
    
    SrEditFrameText:SetText(playerText)
    SrEditFrameHeaderString:SetText('Players')
end

function ChatLootBidder:ToggleSrLock(command)
  if softReserveSessionName == nil then
    Error("No Soft Reserve session loaded")
  else
    if command then
      softReservesLocked = command == "lock"
    else
      softReservesLocked = not softReservesLocked
    end
    MessageStartChannel("Soft Reserves for " .. softReserveSessionName .. " are now " .. (softReservesLocked and "LOCKED" or "UNLOCKED"))
  end
end

function ChatLootBidder:IsLocked()
  return softReservesLocked
end

local InitSlashCommands = function()
	SLASH_ChatLootBidder1, SLASH_ChatLootBidder2 = "/l", "/loot"
	SlashCmdList["ChatLootBidder"] = function(message)
		local commandlist = SplitBySpace(message)
    if commandlist[1] == nil then
      if ChatLootBidderOptionsFrame:IsVisible() then
        ChatLootBidderOptionsFrame:Hide()
      else
        ChatLootBidderOptionsFrame:Show()
      end
    elseif commandlist[1] == "help" or commandlist[1] == "info" then
			ShowHelp()
    elseif commandlist[1] == "sr" then
      if ChatLootBidder_Store.DefaultSessionMode ~= "MSOS" then
        Error("You need to be in MSOS mode to modify Soft Reserve sessions.  `/loot` to change modes.")
        return
      end
      local subcommand = commandlist[2]
      if commandlist[2] == "load" then
        ChatLootBidder:HandleSrLoad(commandlist[3])
      elseif commandlist[2] == "unload" then
        HandleSrUnload()
      elseif commandlist[2] == "delete" then
        ChatLootBidder:HandleSrDelete(commandlist[3])
      elseif commandlist[2] == "show" then
        ChatLootBidder:HandleSrShow()
      elseif commandlist[2] == "csv" or commandlist[2] == "json" or commandlist[2] == "semicolon" or commandlist[2] == "raidresfly" then
        ChatLootBidder:HandleEncoding(commandlist[2])
      elseif commandlist[2] == "lock" or commandlist[2] == "unlock" then
        ChatLootBidder:ToggleSrLock(commandlist[2])
      elseif commandlist[2] == "instructions" then
        ChatLootBidder:HandleSrInstructions()
      else
        Error("Unknown 'sr' subcommand: " .. (commandlist[2] == nil and "nil" or commandlist[2]))
        Error("Valid values are: load, unload, delete, show, lock, unlock, json, semicolon, raidresfly, csv, instructions")
      end
    elseif commandlist[1] == "debug" then
      ChatLootBidder_Store.DebugLevel = ToWholeNumber(commandlist[2])
      Message("Debug level set to " .. ChatLootBidder_Store.DebugLevel)
    elseif commandlist[1] == "bid" and commandlist[2] then
      HandleChannel("BidChannel", commandlist[2])
    elseif commandlist[1] == "session" and commandlist[2] then
      HandleChannel("SessionAnnounceChannel", commandlist[2])
    elseif commandlist[1] == "win" and commandlist[2] then
      HandleChannel("WinnerAnnounceChannel", commandlist[2])
    elseif commandlist[1] == "end" then
      ChatLootBidder:End()
    elseif commandlist[1] == "clear" then
      if commandlist[2] == nil then
        ChatLootBidder:Clear()
      elseif stage == nil then
        Error("The stage is empty")
      else
        local itemLinks = GetItemLinks(message)
        for _, item in pairs(itemLinks) do
          ChatLootBidder:Unstage(item)
        end
      end
      ChatLootBidder:RedrawStage()
    elseif commandlist[1] == "stage" then
      local itemLinks = GetItemLinks(message)
      for _, item in pairs(itemLinks) do
        local item = item
        ChatLootBidder:Stage(item, true)
      end
      ChatLootBidder:RedrawStage()
    elseif commandlist[1] == "summary" then
      BidSummary()
    elseif commandlist[1] == "start" then
      local itemLinks = GetItemLinks(message)
      local minBidOptional = ToWholeNumber(commandlist[getn(commandlist)], 1)
      ChatLootBidder:Start(itemLinks, minBidOptional)
	elseif commandlist[1] == "history" then
		ChatLootBidder:PrintLootHistory()
	elseif commandlist[1] == "clearhistory" then
		ChatLootBidder:ClearLootHistory()
	elseif commandlist[1] == "listen" then
		ChatLootBidder_Store.ListenLootHistory = not ChatLootBidder_Store.ListenLootHistory
		Message('Setting listen history to '..tostring(ChatLootBidder_Store.ListenLootHistory))
	elseif commandlist[1] == "dkp" then
		local bidAddonMessage = "checkDkp=1,MaxOsBid=".. tostring(ChatLootBidder_Store.MaxOsBid)..",MaxTwinkBid=".. tostring(ChatLootBidder_Store.MaxTwinkBid)
		ChatThrottleLib:SendAddonMessage("BULK", "NotChatLootBidder", bidAddonMessage, "RAID")
	else
		-- Stolen logic from SOTA dkp addon (https://github.com/Sentilix/sota)
		sign = string.sub(commandlist[1], 1, 1);
		local number
		if sign == "+" then
			number = tonumber(string.sub(commandlist[1], 2))
			--	Command: +
			--	Syntax: "+<%d> <playername>"
			Debug('Add: '..tostring(number)..' to '..commandlist[2])
			ChatLootBidder:ApplyDKP(commandlist[2], number, false)
		elseif sign == "-" then
			number =  tonumber(string.sub(commandlist[1], 2))
			--	Command: -
			--	Syntax: "-<%d> <playername>"
			Debug('Subtract: '..tostring(number)..' from '..commandlist[2])
			ChatLootBidder:ApplyDKP(commandlist[2], -1*number, false)
		end
	end
  end
end

local function LoadText()
  local k,v,g
  for k,v in pairs(T) do
    if type(k) == "string" then
      g = getglobal("ChatLootBidderOptionsFrame"..k.."Text")
      if g then g:SetText(v) end
    end
  end
end

local function LoadValues()
  local k,v,g,t
  for k,v in pairs(ChatLootBidder_Store) do
    t = type(v)
    g = getglobal("ChatLootBidderOptionsFrame"..k)
    if g and g.SetChecked and t == "boolean" then
      g:SetChecked(v)
    elseif g and k == "DefaultSessionMode" then
      g:SetValue(v == "MSOS" and 1 or 0)
    elseif g and g.SetValue and (t == "string" or t == "number") then
      g:SetValue(v)
    else
      Trace(k .. " <noGui> " .. tostring(v))
    end
  end
end

local function IsValidTier(tier)
  return tier == "ms" or tier == "os" or tier == "twink" or tier == "roll" or tier == "cancel"
end

local function InvalidBidSyntax(item)
  local bidExample = " " .. (ChatLootBidder_Store.MinBid + 9)
  return "Invalid bid syntax for " .. item .. ".  The proper format is: '[item-link] ms" .. (sessionMode == "DKP" and bidExample or "") .. "' or '[item-link] os" .. (sessionMode == "DKP" and bidExample or "") .. "' or '[item-link] twink" .. (sessionMode == "DKP" and bidExample or "") .. "' or '[item-link] roll'"
end

local function of(amt, real)
  if sessionMode == "DKP" then
    return " of " .. realAmt(amt, real)
  end
  return ""
end

local function HandleSrQuery(bidder)
  local sr = Srs(softReserveSessionName)[bidder]
  local msg = "Your Soft Reserve is currently " .. (sr == nil and "not set" or ("[ " .. table.concat(sr, ", ") .. " ]"))
  if softReservesLocked then
    msg = msg .. " LOCKED"
  end
  SendResponse(msg, bidder)
end

local function AtlasLootLoaded()
  return (AtlasLoot_Data and AtlasLoot_Data["AtlasLootItems"]) ~= nil
end

-- Ex/
-- AtlasLoot_Data["AtlasLootItems"]["BWLRazorgore"][1]
-- { 16925, "INV_Belt_22", "=q4=Belt of Transcendence", "=ds=#s10#, #a1# =q9=#c5#", "11%" }
local function ValidateItemName(n)
  if not ChatLootBidder_Store.ItemValidation or not AtlasLootLoaded() then return unpack({-1, n, -1, "", ""}) end
  for raidBossKey,raidBoss in AtlasLoot_Data["AtlasLootItems"] do
    for _,dataSet in raidBoss do
      if dataSet then
        local itemNumber, icon, nameQuery, _, dropRate = unpack(dataSet)
        if nameQuery then
          local _start, _end, _quality, _name = string.find(nameQuery, '^=q(%d)=(.-)$')
          if _name and string.lower(_name) == string.lower(n) then
            return unpack({itemNumber, _name, _quality, raidBossKey, dropRate})
          end
        end
      end
    end
  end
  return nil
end

local function HandleSrAdd(bidder, itemName)
  itemName = Trim(itemName)
  if Srs(softReserveSessionName)[bidder] == nil then
    Srs(softReserveSessionName)[bidder] = {}
  end
  local sr = Srs(softReserveSessionName)[bidder]
  local itemNumber, nameFix, _quality, raidBoss, dropRate = ValidateItemName(itemName)
  if itemNumber == nil then
    SendResponse(itemName .. " does not appear to be a valid item name (AtlasLoot).  If this is incorrect, the Loot Master will need to manually input the item name or disable item validation.", bidder)
  else
    if nameFix ~= itemName then
      SendResponse(itemName .. " fixed to " .. nameFix)
      itemName = nameFix
    end
    table.insert(sr, itemName)
    if TableLength(sr) > ChatLootBidder_Store.DefaultMaxSoftReserves then
      local pop = table.remove(sr, 1)
      if not TableContains(sr, pop) then
        SendResponse("You are no longer reserving: " .. pop, bidder)
      end
    end
  end
  ChatLootBidderOptionsFrame_Reload()
end

function ChatFrame_OnEvent(event)
    -- Non-whispers are ignored; Don't react to duplicate whispers (multiple windows, usually)
    if event ~= "CHAT_MSG_WHISPER" or lastWhisper == (arg1 .. arg2) then
        ChatLootBidder_ChatFrame_OnEvent(event)
        return
    end
    lastWhisper = arg1 .. arg2
    local bidder = arg2

    -- Parse string for a item links
    local items, itemIndexEnd = GetItemLinks(arg1)
    local item = items[1]

    -- Handle SR Bids
    local commandlist = SplitBySpace(arg1)
    if (softReserveSessionName ~= nil and string.lower(commandlist[1] or "") == "sr") then
		if not IsInRaid(bidder) then
		  SendResponse("You must be in the raid to place a Soft Reserve", bidder)
		  return
		end
		if softReserveSessionName == nil then
		  SendResponse("There is no Soft Reserve session loaded", bidder)
		  return
		end
		-- If we're manually editing the SRs, treat it like being locked for incoming additions
		local softReservesLocked = softReservesLocked or SrEditFrame:IsVisible()
		if TableLength(commandlist) == 1 or softReservesLocked then
		  -- skip, query do the query at the end
		elseif commandlist[2] == "clear" or commandlist[2] == "delete" or commandlist[2] == "remove" then
		  Srs(softReserveSessionName)[bidder] = nil
		elseif item ~= nil then
		  local _i
		  for _,_i in pairs(items) do
			HandleSrAdd(bidder, ParseItemNameFromItemLink(_i))
		  end
		else
		  table.remove(commandlist, 1)
		  HandleSrAdd(bidder, table.concat(commandlist, " "))
		end
        HandleSrQuery(bidder)
    -- Ignore all other whispers unless there is an active loot session and there is an item link in the whisper
    elseif session ~= nil and item ~= nil then
        local itemSession = session[item]
        if itemSession == nil then
            local invalidBid = "There is no active loot session for " .. item
            SendResponse(invalidBid, bidder)
            return
        end
        if not IsInRaid(arg2) then
            local invalidBid = "You must be in the raid to send a bid on " .. item
            SendResponse(invalidBid, bidder)
            return
        end

        local mainSpec = itemSession["ms"]
        local offSpec = itemSession["os"]
        local twinkSpec = itemSession["twink"]
        local roll = itemSession["roll"]
        local cancel = itemSession["cancel"]
        local notes = itemSession["notes"]
        local real = itemSession["real"]
		    local minimumBid = itemSession['minBid'] ~= nil and tonumber(itemSession['minBid']) or ChatLootBidder_Store.MinBid
        local bid = SplitBySpace(string.sub(arg1, itemIndexEnd + 1))
        local bidType = NormalizeKeyword(bid[1])
        local tier = bidType and string.lower(bidType) or nil
        local amt = bid[2] and string.lower(bid[2]) or nil
        
        if IsValidTier(tier) then
            amt = ToWholeNumber(amt)
        elseif IsValidTier(amt) then
            -- The bidder mixed up the ms ## to ## ms, handle the mixup
            local oldTier = tier
            tier = amt;
            amt = ToWholeNumber(oldTier)
        else
            SendResponse(InvalidBidSyntax(item), bidder)
            return
        end

        if tier == "cancel" then
          local cancelBid = "Bid canceled for " .. item
          cancel[bidder] = true
          mainSpec[bidder] = nil
          offSpec[bidder] = nil
          twinkSpec[bidder] = nil
          notes[bidder] = nil
          real[bidder] = nil
          MessageBidChannel("<" .. PlayerWithClassColor(bidder) .. "> " .. cancelBid)
          SendResponse(cancelBid, bidder)
          return
        end

        local playerDkp = nil
        if sessionMode == "DKP" and (tier == "ms" or tier == "os" or tier == "twink") then
            playerDkp = ChatLootBidder:GetPlayerDkpFromGuildNotes(bidder)
            if not playerDkp then
                SendResponse("Could not find your DKP balance in guild notes", bidder)
                return
            end
        end
        if sessionMode == "DKP" then
            if tier == "ms" then
                amt = math.min(amt, playerDkp)
                if amt < minimumBid then
                    SendResponse("Your bid ("..amt..") is below minimum bid ("..minimumBid..")", bidder)
                    return
                end
            elseif tier == "os" then
                local maxOsBid = math.ceil(playerDkp * (ChatLootBidder_Store.MaxOsBid/100))
                amt = math.min(amt, maxOsBid)
                if amt < minimumBid then
                    SendResponse("Your bid ("..amt..") is below minimum bid ("..minimumBid..")", bidder)
                    return
                end
            elseif tier == "twink" then
                local maxTwinkBid = math.ceil(playerDkp * (ChatLootBidder_Store.MaxTwinkBid/100))
                amt = math.min(amt, maxTwinkBid)
                if amt < minimumBid then
                    SendResponse("Your bid ("..amt..") is below minimum bid ("..minimumBid..")", bidder)
                    return
                end
            end
        end

        if amt > ChatLootBidder_Store.MaxBid then
            local invalidBid = "Bid for " .. item .. " is too large, the maximum accepted bid is: " .. ChatLootBidder_Store.MaxBid
            SendResponse(invalidBid, bidder)
            return
        end

        -- If they had previously canceled, remove them and allow the new bid to continue
        cancel[bidder] = nil
        if tier == "roll" then
          if roll[bidder] ~= nil and roll[bidder] ~= -1 then
            SendResponse("Your roll of " .. roll[bidder] .. " has already been recorded", bidder)
            return
          end
        elseif sessionMode == "DKP" then
          if amt < minimumBid then
            SendResponse(InvalidBidSyntax(item), bidder)
            return
          end
          -- remove amount from the table for note concat
          table.remove(bid, 2)
        else
          amt = 1
        end
        -- remove tier from the table for note concat
        table.remove(bid, 1)
        local note = table.concat(bid, " ")
        local alt = string.find(string.lower(note), "alt") ~= nil
        real[bidder] = amt
        -- if sessionMode == "DKP" and ChatLootBidder_Store.AltPenalty > 0 and alt then
          -- Trace("Alt penalty is " .. ChatLootBidder_Store.AltPenalty .. "%")
          -- amt = (amt * 100 - amt * ChatLootBidder_Store.AltPenalty) / 100
        -- end
        notes[bidder] = note
        local received
        if tier == "ms" then
          mainSpec[bidder] = amt
          if sessionMode == "MSOS" then roll[bidder] = roll[bidder] or -1 end
          received = "Main Spec bid" .. of(amt, real[bidder]) .. " received for " .. item .. AppendNote(note)
        elseif mainSpec[bidder] ~= nil then
          SendResponse("You already have a MS bid" .. of(mainSpec[bidder], real[bidder]) .. " recorded. Use '[item-link] cancel' to cancel your current MS bid.", bidder)
          return
        elseif tier == "os" then
          offSpec[bidder] = amt
          if sessionMode == "MSOS" then roll[bidder] = roll[bidder] or -1 end
          received = "Off Spec bid" .. of(amt, real[bidder]) .. " received for " .. item .. AppendNote(note)
        elseif offSpec[bidder] ~= nil then
          SendResponse("You already have an OS bid" .. of(offSpec[bidder], real[bidder]) .. " recorded. Use '[item-link] cancel' to cancel your current MS bid.", bidder)
          return
        elseif tier == "twink" then
          twinkSpec[bidder] = amt
          if sessionMode == "MSOS" then roll[bidder] = roll[bidder] or -1 end
          received = "Twink bid" .. of(amt, real[bidder]) .. " received for " .. item .. AppendNote(note)
        elseif twinkSpec[bidder] ~= nil then
          SendResponse("You already have a Twink bid" .. of(twinkSpec[bidder], real[bidder]) .. " recorded. Use '[item-link] cancel' to cancel your current MS bid.", bidder)
          return
        elseif tier == "roll" then
          roll[bidder] = -1
          received = "Your roll bid for " .. item .. " has been received" .. AppendNote(note) .. ".  '/random' now to record your own roll or do nothing for the addon to roll for you at the end of the session."
        end
        MessageBidChannel("<" .. PlayerWithClassColor(bidder) .. "> " .. tier .. ((sessionMode == "MSOS" or amt == nil or tier == "roll") and "" or (" " .. realAmt(amt, real[bidder]))) .. " " .. item)
        SendResponse(received, bidder)
        return

    else
        ChatLootBidder_ChatFrame_OnEvent(event)
    end
end

function ChatLootBidder:StartSessionButtonShown()
  ChatLootBidder:Show()
  startSessionButton:Show()
  clearSessionButton:Show()
end

function ChatLootBidder:EndSessionButtonShown()
  ChatLootBidder:Show()
  startSessionButton:Hide()
  -- clearSessionButton:Hide()
  endSessionButton:Show()
  -- ChatLootBidder:SetHeight(50)
  for i = 1, 8 do
    local stageItem = getglobal(ChatLootBidder:GetName() .. "Item"..i)
    local unstageButton = getglobal(ChatLootBidder:GetName() .. "UnstageButton"..i)
    unstageButton:Hide()
    stageItem:SetText("")
    stageItem:Hide()
  end
end

function ChatLootBidder:RedrawStage()
  local i=1, k, show
  for k, show in pairs(stage or {}) do
    if show then
      if i == 9 then Error("You may only stage up to 8 items.  Use /loot clear [itm] to clear specific items or /clear to wipe it clean."); return end
      if not ChatLootBidder:IsVisible() then
        ChatLootBidder:StartSessionButtonShown()
      end
      local stageItem = getglobal(ChatLootBidder:GetName() .. "Item"..i)
      local unstageButton = getglobal(ChatLootBidder:GetName() .. "UnstageButton"..i)
      unstageButton:Show()
      stageItem:SetText(k)
      stageItem:Show()
      i = i + 1
    end
  end
  if i == 1 then -- if none shown
    ChatLootBidder:Hide()
  else
    ChatLootBidder:SetHeight(240-(160-i*20))
    for i = i, 8 do
      local stageItem = getglobal(ChatLootBidder:GetName() .. "Item"..i)
      local unstageButton = getglobal(ChatLootBidder:GetName() .. "UnstageButton"..i)
      unstageButton:Hide()
      stageItem:SetText("")
      stageItem:Hide()
    end
  end
  getglobal(ChatLootBidder:GetName() .. "HeaderString"):SetText(ChatLootBidder_Store.DefaultSessionMode .. " Mode")
end

function ChatLootBidder:Stage(i, force)
  stage = stage or {}
  if force or stage[i] == nil then
    stage[i] = true
  end
end

function ChatLootBidder.CHAT_MSG_SYSTEM(msg)
  if session == nil then return end
  local _, _, name, roll, low, high = string.find(msg, rollRegex)
	if name then
    if tonumber(low) > 1 or tonumber(high) > 100 then return end -- invalid roll
    if name == me and tonumber(high) <= 40 then return end -- master looter using pfUI's random loot distribution
    local existingWhy = ""
    for item,itemSession in pairs(session) do
      local existingRoll = itemSession["roll"][name]
      if existingRoll == -1 or ((1 == getn(GetKeys(session))) and existingRoll == nil) then
        itemSession["roll"][name] = tonumber(roll)
        SendResponse("Your roll of " .. roll .. " been recorded for " .. item, name)
        return
      elseif (existingRoll or 0) > 0 then
        existingWhy = existingWhy .. "Your roll of " .. existingRoll .. " has already been recorded for " .. item .. ". "
      end
    end
    if string.len(existingWhy) > 0 then
      SendResponse("Ignoring your roll of " .. roll .. ". " .. existingWhy, name)
    elseif sessionMode == "DKP" then
      SendResponse("Ignoring your roll of " .. roll .. ". You must first declare that you are rolling on an item first: '/w " .. me .. " [item-link] roll'", name)
    else
      SendResponse("Ignoring your roll of " .. roll .. ". You must bid on an item before rolling on it: '/w " .. me .. " [item-link] ms/os/roll'", name)
    end
	end
end

function ChatLootBidder.ADDON_LOADED()
  LoadVariables()
  InitSlashCommands()
  -- Load Options.xml values
  LoadText()
  LoadValues()
  this:UnregisterEvent("ADDON_LOADED")
end

function ChatLootBidder.CHAT_MSG_ADDON(addonTag, stringMessage, channel, sender)
    if VersionUtil:CHAT_MSG_ADDON(addonName, function(ver)
        Message("New version " .. ver .. " of " .. addonTitle .. " is available! Upgrade now at " .. addonNotes)
    end) then 
        return 
    end
    if addonTag == addonName and sender ~= me and IsInRaid(sender) and IsRaidAssistant(sender) and IsRaidAssistant(me) and ChatLootBidder_Store.ListenLootHistory then
        Debug('GOTCHA '..stringMessage..' from '..sender)
        
        local success, record = pcall(function()
            local parts = {}
            for part in gfind(stringMessage, "([^,]+)") do
                table.insert(parts, Trim(part))
            end
            
            if getn(parts) >= 6 then
                return {
                    character = parts[1],
                    item = parts[2],
                    bid_type = parts[3],
                    bid_amount = parts[4] ~= "" and tonumber(parts[4]) or nil,
                    boss = parts[5],
                    datetime = parts[6]
                }
            end
            return nil
        end)
        
        if success and record and record.character and record.item then
            local isDuplicate = false
            for _, existing in ipairs(ChatLootBidder_LootHistory) do
                if existing.character == record.character and 
                   existing.item == record.item and 
                   existing.datetime == record.datetime then
                    isDuplicate = true
                    break
                end
            end
            
            if not isDuplicate then
                table.insert(ChatLootBidder_LootHistory, record)
                Debug(string.format("Added loot record from %s: %s won %s (%s)", 
                    sender, record.character, record.item, record.bid_type))
                
                -- Обновляем UI если окно истории открыто
                if SrEditFrame:IsVisible() and SrEditFrameHeaderString:GetText() == 'LootHistory' then
                    ChatLootBidder:HandleShowLootHistory()
                end
            else
                Debug("Duplicate loot record ignored")
            end
        elseif not success then
            Debug("Failed to parse loot message: "..tostring(record))
        end
    end
end

function ChatLootBidder.PARTY_MEMBERS_CHANGED()
  VersionUtil:PARTY_MEMBERS_CHANGED(addonName)
end

function ChatLootBidder.PLAYER_ENTERING_WORLD()
  VersionUtil:PLAYER_ENTERING_WORLD(addonName)
  if ChatLootBidder_Store.Point and getn(ChatLootBidder_Store.Point) == 4 then
    ChatLootBidder:SetPoint(ChatLootBidder_Store.Point[1], "UIParent", ChatLootBidder_Store.Point[2], ChatLootBidder_Store.Point[3], ChatLootBidder_Store.Point[4])
  end
end

function ChatLootBidder.PLAYER_LEAVING_WORLD()
  local point, _, relativePoint, xOfs, yOfs = ChatLootBidder:GetPoint()
  ChatLootBidder_Store.Point = {point, relativePoint, xOfs, yOfs}
end

function ChatLootBidder.LOOT_OPENED()
  if session ~= nil then return end
  if not ChatLootBidder_Store.AutoStage then return end
  -- if not IsMasterLooterSet() or not IsRaidAssistant(me) then return end
  if not IsRaidAssistant(me) then return end
  local i
  for i=1, GetNumLootItems() do
    local lootIcon, lootName, lootQuantity, rarity, locked, isQuestItem, questId, isActive = GetLootSlotInfo(i)
    -- print(lootIcon, lootName, lootQuantity, rarity, locked, isQuestItem, questId, isActive)
    if rarity >= ChatLootBidder_Store.MinRarity and rarity <= ChatLootBidder_Store.MaxRarity then
      ChatLootBidder:Stage(GetLootSlotLink(i))
    end
  end
  ChatLootBidder:RedrawStage()
end

function ChatLootBidder.PLAYER_TARGET_CHANGED()
	local unitid
	local isBoss = UnitLevel("target") == -1
	if isBoss then
		unitid = "target"
		bossName = UnitName(unitid)
	end
	if bossName ~= nil and bosses[bossName] then
		bossName = bosses[bossName]
	end
end


-- [00:00]Autozhot: Autozhot - Band of Accuria
local function ParseRaidResFly(text)
  local line, t = nil, {}
  for line in gfind(text, '([^\n]+)') do
    local _, _, name, item = string.find(line, "^.-: ([%a]-) . (.-)$")
    name = Trim(name)
    item = Trim(item)
    if t[name] == nil then t[name] = {} end
    table.insert(t[name], item)
  end
  return t
end

-- Autozhot ; Band of Accuria ; Giantstalker Boots
local function ParseSemicolon(text)
  local t, line, part, k, v = {}, nil, nil, nil, {}
  for line in gfind(text, '([^\n]+)') do
    for part in gfind(line, '([^;]+)') do
      if k == nil then
        k = Trim(part)
      else
        local sr = Trim(part)
        table.insert(v, sr)
      end
    end
    t[k] = v
    k = nil
    v = {}
  end
  return t
end

function ValidateFixAndWarn(t)
  local k,k2,v,i,len
  for k,v in pairs(t) do
    len = getn(v)
    if len > ChatLootBidder_Store.DefaultMaxSoftReserves then
      Error(k .. " has " .. len .. " soft reserves loaded (max=" .. ChatLootBidder_Store.DefaultMaxSoftReserves .. ")")
    end
    for k2,i in pairs(v) do
      local itemNumber, nameFix, _, _, _ = ValidateItemName(i)
      if itemNumber == nil then
        Error(i .. " does not appear to be a valid item name (AtlasLoot)")
      elseif nameFix ~= i then
        Message(i .. " fixed to " .. nameFix)
        v[k2] = nameFix
      end
    end
  end
end

function ChatLootBidder:DecodeAndSave(text, parent)
  local encoding = SrEditFrameHeaderString:GetText()
  local t
  if encoding == "json" then
	t = json.decode(text)
  elseif encoding == "csv" then
	t = UnFlatten(csv:fromCSV(text))
  elseif encoding == "raidresfly" then
	t = ParseRaidResFly(text)
  elseif encoding == "semicolon" then
	t = ParseSemicolon(text)
  else
	Error("No encoding provided")
	return
  end
  ValidateFixAndWarn(t)
  ChatLootBidder_Store.SoftReserveSessions[softReserveSessionName] = t
  ChatLootBidderOptionsFrame_Reload()
  parent:Hide()
end

function ChatLootBidder:DecodeLootHistoryAndSave(text, parent)
  Debug('Trying to save loothistory...')
  local t = UnflattenLootHistory(csv:fromCSV(text))
  -- Make checking data here
  ChatLootBidder_LootHistory = t
  ChatLootBidder:PrintLootHistory()
  ChatLootBidderOptionsFrame_Reload()
  parent:Hide()
end


function ChatLootBidder:DecodeImportDkpAndSave(text, parent)
    Debug('Starting DKP import...')
    
    local csvData = csv:fromCSV(text)
    if not csvData or getn(csvData) == 0 then
        Error("Invalid or empty CSV data")
        parent:Hide()
        return
    end

    local raidLookup = {}
    if IsInRaid(me) then
        for i = 1, GetNumRaidMembers() do
            local name = GetRaidRosterInfo(i)
            if name then
                raidLookup[ChatLootBidder:CapitalizeStr(name)] = true
            end
        end
    else
        Error("You must be in a raid to import DKP")
        parent:Hide()
        return
    end

    local importData = {}
    for _, row in ipairs(csvData) do
        if getn(row) >= 2 then
            local name = ChatLootBidder:CapitalizeStr(row[1])
            if raidLookup[name] then
                importData[name] = {
                    dkp = tonumber(row[2]) or 0,
                    isMain = (getn(row) >= 3) and (tonumber(row[3]) or 0)
                }
            end
        end
    end

    local memberCount = GetNumGuildMembers()
    local processed = 0
    local skipped = 0

    for i = 1, memberCount do
        local name, _, _, _, _, _, publicNote = GetGuildRosterInfo(i)
        name = name and ChatLootBidder:CapitalizeStr(name)

        if name and importData[name] then
            local newDkp = importData[name].dkp
            local newNote = publicNote or ""
			local dkpPattern = "<(-?%d+)>"
            if newNote then
                if string.find(newNote, dkpPattern) then
					newNote = string.gsub(newNote, dkpPattern, ChatLootBidder:CreateDkpString(newDkp), 1)
                else
                    newNote = newNote..ChatLootBidder:CreateDkpString(newDkp)
                end
            else
				newNote = newNote..(newNote ~= "" and " " or "")..ChatLootBidder:CreateDkpString(newDkp)
            end
            GuildRosterSetPublicNote(i, newNote)
            processed = processed + 1
            Debug(string.format("Set DKP for %s to %d", name, newDkp))
        end
    end

    for name, _ in pairs(importData) do
        if not string.find(name, ",") then
            local found = false
            for i = 1, memberCount do
                local guildName = GetGuildRosterInfo(i)
                if guildName and ChatLootBidder:CapitalizeStr(guildName) == name then
                    found = true
                    break
                end
            end
            if not found then
                skipped = skipped + 1
                Debug(string.format("%s not found in guild", name))
            end
        end
    end

    GuildRoster()
    Message(string.format("DKP import complete: %d updated, %d not in guild", 
        processed, skipped))
    
    parent:Hide()
end


--
-- Taken from https://github.com/laytya/WowLuaVanilla which took it from SuperMacro
function ChatLootBidder:OnVerticalScroll(scrollFrame)
	local offset = scrollFrame:GetVerticalScroll();
	local scrollbar = getglobal(scrollFrame:GetName().."ScrollBar");

	scrollbar:SetValue(offset);
	local min, max = scrollbar:GetMinMaxValues();
	local display = false;
	if ( offset == 0 ) then
	    getglobal(scrollbar:GetName().."ScrollUpButton"):Disable();
	else
	    getglobal(scrollbar:GetName().."ScrollUpButton"):Enable();
	    display = true;
	end
	if ((scrollbar:GetValue() - max) == 0) then
	    getglobal(scrollbar:GetName().."ScrollDownButton"):Disable();
	else
	    getglobal(scrollbar:GetName().."ScrollDownButton"):Enable();
	    display = true;
	end
	if ( display ) then
		scrollbar:Show();
	else
		scrollbar:Hide();
	end
end

-- Функция для вывода истории лута в чат
function ChatLootBidder:PrintLootHistory()
    if getn(ChatLootBidder_LootHistory) == 0 then
        Message("Loot history is empty")
        return
    end
    
    Message("=== Loot History ===")
    for i=1,getn(ChatLootBidder_LootHistory) do
        local record = ChatLootBidder_LootHistory[i]
        local line = string.format("%s, %s, %s%s%s",
            record.character,
            record.item,
            record.bid_type,
            record.bid_amount ~= nil and (", " .. record.bid_amount) or ",",
            record.boss ~= nil and (", " .. record.boss) or ",",
            record.datetime ~= nil and (", " .. record.datetime) or ",")
        Message(line)
    end
end

function ChatLootBidder:ClearLootHistory()
    ChatLootBidder_LootHistory = {}
    Message("Loot history cleared")
end

function ChatLootBidder:SetDKP(playername, dkpValue, silentmode)
    if not playername or type(playername) ~= "string" or playername == "" then
        if not silentmode then
            Error("Invalid player name")
        end
        return false
    end
    
    dkpValue = dkpValue or 0
    playername = ChatLootBidder:CapitalizeStr(playername)
    
    Debug("Setting DKP for "..playername..": "..dkpValue)
    
    local memberCount = GetNumGuildMembers()
    for i = 1, memberCount do
        local name, _, _, _, _, _, publicNote = GetGuildRosterInfo(i)
        if name == playername then
            Debug("Found player in guild roster")
            local newNote = publicNote or ""
            local currentDKP = 0
            local dkpPattern = "<(-?%d+)>"
            
            local startPos, endPos, dkpStr = string.find(newNote, dkpPattern)
            
            if dkpStr and tonumber(dkpStr) then
                currentDKP = tonumber(dkpStr)
                Debug("Current DKP found: "..currentDKP.." and reseting...")
                newNote = string.gsub(newNote, dkpPattern, ChatLootBidder:CreateDkpString(dkpValue), 1)
            else
                Debug("No DKP record found, creating new one")
                newNote = newNote..(newNote ~= "" and " " or "")..ChatLootBidder:CreateDkpString(dkpValue)
            end
            
            Debug("New note: "..newNote)
            
            GuildRosterSetPublicNote(i, newNote)
            
            if not silentmode then
                Message(string.format("Updated DKP for %s: %+d (Total: %d)", 
                    playername, dkpValue, currentDKP + dkpValue))
            end
            
            return true
        end
    end
    
    if not silentmode then
        Message(string.format("%s was not found in the guild; DKP was not updated.", playername))
    end
    return false
end


function ChatLootBidder:ApplyDKP(playername, dkpValue, silentmode)
    if not playername or type(playername) ~= "string" or playername == "" then
        if not silentmode then
            Error("Invalid player name")
        end
        return false
    end
    
    dkpValue = dkpValue or 0
    playername = ChatLootBidder:CapitalizeStr(playername)
    
    Debug("Applying DKP for "..playername..": "..dkpValue)
    
    local memberCount = GetNumGuildMembers()
    for i = 1, memberCount do
        local name, _, _, _, _, _, publicNote = GetGuildRosterInfo(i)
        if name == playername then
            Debug("Found player in guild roster")
            local newNote = publicNote or ""
            local currentDKP = 0
            local dkpPattern = "<(-?%d+)>"
            
            local startPos, endPos, dkpStr = string.find(newNote, dkpPattern)
            
            if dkpStr and tonumber(dkpStr) then
                currentDKP = tonumber(dkpStr)
                Debug("Current DKP found: "..currentDKP)
                newNote = string.gsub(newNote, dkpPattern, ChatLootBidder:CreateDkpString(currentDKP + dkpValue), 1)
            else
                Debug("No DKP record found, creating new one")
                newNote = newNote..(newNote ~= "" and " " or "")..ChatLootBidder:CreateDkpString(dkpValue)
            end
            
            Debug("New note: "..newNote)
            
            GuildRosterSetPublicNote(i, newNote)
            
            if not silentmode then
                Message(string.format("Updated DKP for %s: %+d (Total: %d)", 
                    playername, dkpValue, currentDKP + dkpValue))
            end
            
            return true
        end
    end
    
    if not silentmode then
        Message(string.format("%s was not found in the guild; DKP was not updated.", playername))
    end
    return false
end


function ChatLootBidder:GetPlayerDkpFromGuildNotes(playerName)
    local memberCount = GetNumGuildMembers()
    for i = 1, memberCount do
        local name, _, _, _, _, _, publicNote = GetGuildRosterInfo(i)
        if name and ChatLootBidder:CapitalizeStr(name) == ChatLootBidder:CapitalizeStr(playerName) then
            local _, _, dkp = string.find(publicNote or "", "<(-?%d+)>")
            return tonumber(dkp) or 0
        end
    end
    return nil
end


function ChatLootBidder:UpdatePlayerDkpInGuildNotes(playerName, newDkp)
    local memberCount = GetNumGuildMembers()
    for i = 1, memberCount do
        local name, _, _, _, _, _, publicNote = GetGuildRosterInfo(i)
        if name and ChatLootBidder:CapitalizeStr(name) == ChatLootBidder:CapitalizeStr(playerName) then
            local newNote = publicNote or ""
			local dkpPattern = "<(-?%d+)>"
            if newNote then
                if string.find(publicNote, dkpPattern) then
					newNote = string.gsub(newNote, dkpPattern, ChatLootBidder:CreateDkpString(newDkp), 1)
                else
                    newNote = publicNote..ChatLootBidder:CreateDkpString(newDkp)
                end
            else
				newNote = newNote..(newNote ~= "" and " " or "")..ChatLootBidder:CreateDkpString(newDkp)
            end
            Debug("New note: "..newNote)
            
            GuildRosterSetPublicNote(i, newNote)
            return true
        end
    end
    return false
end


function ChatLootBidder:CreateDkpString(dkp)
	local result;
	if not dkp or dkp == "" or not tonumber(dkp) then
		dkp = 0;
	end
	dkp = tonumber(dkp);
	local dkpLen = 5;
	if dkpLen > 0 then
		local dkpStr = "".. abs(dkp)
		while string.len(dkpStr) < dkpLen do
			dkpStr = "0"..dkpStr;
		end
		if dkp < 0 then
			dkpStr = "-"..dkpStr;
		end				
		result = "<"..dkpStr..">";
	else
		result = "<"..dkp..">";
	end
	return result;
end

function ChatLootBidder:CapitalizeStr(msg)
	if not msg then
		return ""
	end	

	local f = string.sub(msg, 1, 1)
	local r = string.sub(msg, 2)
	return string.upper(f) .. string.lower(r)
end