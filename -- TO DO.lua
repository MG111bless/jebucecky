-- TO DO 
-- UPGRADE TO X TIER
-- CHECKS FOR DOTTED BOX
-- MULTIPLE QUESTS AT ONCE
-- CHECK FOR TP TO W2/3/4

repeat task.wait() until game:IsLoaded()
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
repeat task.wait() until not LocalPlayer.PlayerGui:FindFirstChild("__INTRO")
repeat task.wait() until LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Library = ReplicatedStorage.Library
local Client = Library.Client
local Network = require(Client.Network)
local Save = require(Client.Save).Get()
local MapCmds = require(Client.MapCmds)
local ZoneCmds = require(Client.ZoneCmds)
local EggCmds = require(Client.EggCmds)
local ZonesUtil = require(Library.Util.ZonesUtil)
local OrbCmds = require(Client.OrbCmds)
local virtualInput = game:GetService("VirtualInputManager")
local PetNetworking = require(Library.Client.PetNetworking)  
local BreakableFrontend = require(Client.BreakableFrontend)
local InstancingCmds = require(Client.InstancingCmds)
local RCmds = require(Client.RankCmds)

local function getHRP()
    return LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
end

local PlayerPet = require(ReplicatedStorage.Library.Client.PlayerPet)
hookfunction(PlayerPet.CalculateSpeedMultiplier, function() return math.huge end)

local Eggs = LocalPlayer.PlayerScripts.Scripts.Game["Egg Opening Frontend"]
if Eggs then getsenv(Eggs).PlayEggAnimation = function() return end end

OrbCmds.CombineDelay, OrbCmds.CollectDistance, OrbCmds.DefaultPickupDistance, OrbCmds.CombineDistance = -math.huge, math.huge, math.huge, math.huge
hookfunction(getconnections(Network.Fired("Orbs: Create"))[1].Function, function(Data)
    local Orbs = {}
    for i,v in ipairs(Data) do
        table.insert(Orbs, v.id)
        Network.Fire("Orbs: Collect", Orbs)
    end
end)

task.spawn(function()
    while true do
        virtualInput:SendKeyEvent(true, "Space", false, game)
        task.wait(0.1)
        virtualInput:SendKeyEvent(false, "Space", false, game)
        task.wait(100)
    end
end)

task.spawn(function()
    while task.wait(1) do
        pcall(function() Network.Fire("Idle Tracking: Stop Timer") end)
    end
end)

local NetworkEquippedPets = {}
local lastPetUpdate = 0
local consecutiveNoPetAttempts = 0
local MAX_NO_PET_ATTEMPTS = 5
local NO_PET_CHECK_INTERVAL = 5

local function getPlayerPosition()
    local character = LocalPlayer.Character
    if not character then return nil end
    local hrp = character:FindFirstChild("HumanoidRootPart")
    return hrp and hrp.Position or nil
end

local function updateNetworkEquippedPets()
    local now = tick()
    if now - lastPetUpdate < 0.5 then return end

    pcall(function()
        NetworkEquippedPets = {}
        lastPetUpdate = now
        if not PetNetworking or not PetNetworking.EquippedPets then return end
        local success, equippedPetData = pcall(PetNetworking.EquippedPets)
        if not success or not equippedPetData or type(equippedPetData) ~= "table" then return end
        for _, petData in pairs(equippedPetData) do
            if petData and petData.euid then
                table.insert(NetworkEquippedPets, petData.euid)
            end
        end
    end)
end

local function getBreakablesInRadius()
    local playerPos = getPlayerPosition()
    if not playerPos then return {} end

    local breakables = {}
    pcall(function()
        if InstancingCmds.IsInInstance() then
            local approaches = {
                function() return BreakableFrontend.AllByInstanceAndClass("Normal") end,
                function() return BreakableFrontend.AllByInstanceAndClass("Chest") end,
                function() return BreakableFrontend.AllByInstanceAndClasses("Normal", "Chest") end,
            }
            
            for _, approach in ipairs(approaches) do
                local success, result = pcall(approach)
                if success and result and next(result) then
                    for uid, breakable in pairs(result) do
                        if breakable and breakable.position then
                            breakables[uid] = breakable
                        end
                    end
                    break
                end
            end
            
            if next(breakables) == nil then
                pcall(function()
                    local breakableFolder = workspace:FindFirstChild("__THINGS")
                    if breakableFolder then
                        breakableFolder = breakableFolder:FindFirstChild("Breakables")
                    end
                    
                    if breakableFolder then
                        for _, model in pairs(breakableFolder:GetChildren()) do
                            if model:IsA("Model") and model.PrimaryPart then
                                local uid = model:GetAttribute("BreakableUID")
                                local disableDamage = model:GetAttribute("DisableDamage")
                                local owner = model:GetAttribute("OwnerUsername")
                                
                                if uid and not disableDamage and (not owner or owner == LocalPlayer.Name) then
                                    breakables[uid] = {
                                        uid = uid,
                                        position = model:GetPivot().Position,
                                        disableDamage = false,
                                        dir = {NoTapping = false},
                                        modifier = owner and {Owner = owner} or {}
                                    }
                                end
                            end
                        end
                    end
                end)
            end
        else
            local currentZone = MapCmds.GetCurrentZone()
            if currentZone then
                local zoneBreakables = BreakableFrontend.AllByZoneAndClass(currentZone, "Normal")
                for uid, breakable in pairs(zoneBreakables) do
                    if breakable and breakable.position then
                        breakables[uid] = breakable
                    end
                end
            end
        end
    end)

    local nearbyBreakables = {}
    for uid, breakable in pairs(breakables) do
        if not breakable.disableDamage and
           not (breakable.dir and breakable.dir.NoTapping) and
           not (breakable.modifier and breakable.modifier.Owner and breakable.modifier.Owner ~= LocalPlayer.Name) then
            local distance = (playerPos - breakable.position).Magnitude
            table.insert(nearbyBreakables, {uid = uid, distance = distance})
        end
    end

    table.sort(nearbyBreakables, function(a, b) return a.distance < b.distance end)
    return nearbyBreakables
end

local function NetworkFarmBreakables()
    pcall(function()
        updateNetworkEquippedPets()
        
        if #NetworkEquippedPets == 0 then
            consecutiveNoPetAttempts = consecutiveNoPetAttempts + 1
            
            if consecutiveNoPetAttempts >= MAX_NO_PET_ATTEMPTS then
                consecutiveNoPetAttempts = 0
                print("No pets equipped for too long - something might be wrong")
                return
            end
            
            return
        end

        if consecutiveNoPetAttempts > 0 then
            consecutiveNoPetAttempts = 0
        end

        local nearbyBreakables = getBreakablesInRadius()
        if #nearbyBreakables == 0 then return end

        local RemoteList = {}
        for i, petEUID in ipairs(NetworkEquippedPets) do
            local breakableIndex = ((i - 1) % #nearbyBreakables) + 1
            RemoteList[petEUID] = nearbyBreakables[breakableIndex].uid
        end

        if next(RemoteList) then
            pcall(function()
                Network.UnreliableFire("Breakables_PlayerDealDamage", nearbyBreakables[1].uid)
                Network.Fire("Breakables_JoinPetBulk", RemoteList)
            end)
        end
    end)
end

pcall(function()
    if not Network or not Network.Fired then return end
    local petUpdateEvents = {"Pets_LocalPetsUpdated", "Pets_LocalPetsUnequipped", "Pets_LocalPetsEquipped"}
    for _, eventName in ipairs(petUpdateEvents) do
        local connection = Network.Fired(eventName)
        if connection then
            connection:Connect(function() lastPetUpdate = 0 end)
        end
    end
end)

task.spawn(function()
    while true do
        NetworkFarmBreakables()
        
        local waitTime = (#NetworkEquippedPets == 0) and NO_PET_CHECK_INTERVAL or 0.1
        task.wait(waitTime)
    end
end)

local activeQuests = {}
local pauseZoneProgression = false
local pauseZoneBuying = false
local completedQuests = {}

local QUEST_TYPES = {
    [15] = "collect_enchants",
    [35] = "fruits",
    [14] = "collect_potions",
    [34] = "tier_potions",
    [3] = "hatch",
    [20] = "hatch_best",
    [40] = "golden_pets",
    [41] = "rainbow_pets",
    [33] = "flags",
    [38] = "comets_best",
    [37] = "coin_jars_best",
    [31] = "coin_jars",
    [32] = "comets",
    [44] = "lucky_blocks_best",
    [67] = "lucky_blocks",
    [43] = "pinatas_best",
    [66] = "pinatas",
}

local GOLD_MACHINE_CFRAME = CFrame.new(336.360168, 13.5504131, 1319.11304, -0.0173809528, 0, 0.999849021, 0, 1, 0, -0.999849021, 0, -0.0173809528)
local RAINBOW_MACHINE_CFRAME = CFrame.new(658.953857, 13.5827112, 1795.63782, -0.0173809528, 0, 0.999849021, 0, 1, 0, -0.999849021, 0, -0.0173809528)

local function extractAmount(questData)
    if type(questData) == "table" and questData.amount then
        return questData.amount
    end
    
    if type(questData) == "string" then
        local number = tonumber(string.match(questData, "(%d+)"))
        return number or (string.find(questData, " a ") and 1 or 1)
    end
    
    return 1
end

local function extractTier(questText)
    local romanTier = string.match(questText, "Tier (%w+)")
    if not romanTier then return nil end
    local romanNumerals = {I = 1, V = 5, X = 10, L = 50, C = 100, D = 500, M = 1000}
    local arabic, prevValue = 0, 0
    for i = #romanTier, 1, -1 do
        local value = romanNumerals[string.sub(romanTier, i, i)]
        if value then
            arabic = arabic + (value < prevValue and -value or value)
            prevValue = value
        end
    end
    return arabic
end

local function getEligiblePetsInInventory(target_pt, exclude_pt)
    local eligiblePets = {}
    
    for UID, data in pairs(Save.Inventory.Pet) do
        if data and data.id and data._am then
            if data.pt ~= exclude_pt then
                if (target_pt == nil and not data.pt) or (data.pt == target_pt) then
                    if not eligiblePets[data.id] then
                        eligiblePets[data.id] = {count = 0, uids = {}}
                    end
                    eligiblePets[data.id].count = eligiblePets[data.id].count + data._am
                    table.insert(eligiblePets[data.id].uids, UID)
                end
            end
        end
    end
    
    return eligiblePets
end

local function progressToMaxZone()
    local HRP = getHRP()
    if not HRP then 
        print("No HRP found!")
        return false 
    end
    
    local maxOwnedZoneID = ZoneCmds.GetMaxOwnedZone()
    local currentZoneID = MapCmds.GetCurrentZone()
    
    if currentZoneID == maxOwnedZoneID then
        return true
    end
    
    local maxZoneNum = 0
    for _, zoneData in pairs(ZonesUtil.GetArray()) do
        if zoneData._id == maxOwnedZoneID then 
            maxZoneNum = zoneData.ZoneNumber 
            break 
        end
    end
    
    local targetZoneID, targetBiggestZone, targetZoneNumber
    for i = maxZoneNum, 1, -1 do
        local zoneID = ZonesUtil.GetZoneFromNumber(i)
        if zoneID then
            local breakZones = ZonesUtil.GetBreakableZones(zoneID)
            if breakZones and #breakZones:GetChildren() > 0 then
                targetZoneID, targetZoneNumber = zoneID, i
                targetBiggestZone = breakZones:GetChildren()[1]
                for _, zone in pairs(breakZones:GetChildren()) do
                    if zone.Size.Magnitude > targetBiggestZone.Size.Magnitude then
                        targetBiggestZone = zone
                    end
                end
                break
            end
        end
    end
    
    if targetZoneID and targetBiggestZone and targetZoneNumber then
        local currentPos = HRP.Position
        local targetPos = targetBiggestZone.CFrame.Position
        print("Teleporting to zone center")
        
        local distance = (currentPos - targetPos).Magnitude
        
        if distance > 10 then
            print("Teleporting to zone", targetZoneNumber, "- distance:", math.floor(distance))
            HRP.CFrame = CFrame.new(targetPos + Vector3.new(0, 10, 0))
            task.wait(0.5)
        else
            print("Already near target zone", targetZoneNumber, "- distance:", math.floor(distance))
        end
        return true
    end
    
    return false
end

local function progressZone()
    if pauseZoneProgression then return false end
    
    local HRP = getHRP()
    if not HRP then return false end
    
    local maxOwnedZoneID = ZoneCmds.GetMaxOwnedZone()
    local maxZoneNum = 0
    for _, zoneData in pairs(ZonesUtil.GetArray()) do
        if zoneData._id == maxOwnedZoneID then 
            maxZoneNum = zoneData.ZoneNumber 
            break 
        end
    end
    
    local targetZoneID, targetBiggestZone, targetZoneNumber
    for i = maxZoneNum, 1, -1 do
        local zoneID = ZonesUtil.GetZoneFromNumber(i)
        if zoneID then
            local breakZones = ZonesUtil.GetBreakableZones(zoneID)
            if breakZones and #breakZones:GetChildren() > 0 then
                targetZoneID, targetZoneNumber = zoneID, i
                targetBiggestZone = breakZones:GetChildren()[1]
                for _, zone in pairs(breakZones:GetChildren()) do
                    if zone.Size.Magnitude > targetBiggestZone.Size.Magnitude then
                        targetBiggestZone = zone
                    end
                end
                break
            end
        end
    end

    if targetZoneID and targetBiggestZone and targetZoneNumber then
        local currentPos = HRP.Position
        local targetPos = targetBiggestZone.CFrame.Position
        print("Teleporting to zone center")
        
        local distance = (currentPos - targetPos).Magnitude
        
        if distance > 10 then
            print("Progressing to zone:", targetZoneNumber, "- distance:", math.floor(distance))
            HRP.CFrame = CFrame.new(targetPos + Vector3.new(0, 5, 0))
        else
            print("Already at target zone", targetZoneNumber, "- distance:", math.floor(distance))
        end
        return true
    end
    
    return false
end

local function moveToMaxZone()
    return progressZone()
end

local function getBestEggData()
    local highestEggNumber = EggCmds.GetHighestEggNumberAvailable()
    local world1EggsDirectory = game:GetService("ReplicatedStorage").__DIRECTORY.Eggs["Zone Eggs"]["World 1"]
    if not world1EggsDirectory then return nil, nil end

    for _, subFolder in pairs(world1EggsDirectory:GetChildren()) do
        if subFolder:IsA("Folder") then
            for _, eggDataInSubFolder in pairs(subFolder:GetChildren()) do
                local currentEggNumber = tonumber(string.match(eggDataInSubFolder.Name, "^(%d+)"))
                if currentEggNumber == highestEggNumber then
                    local eggName = eggDataInSubFolder.Name:match("| (.+)$") or eggDataInSubFolder.Name
                    return eggName, require(eggDataInSubFolder)
                end
            end
        end
    end
    return nil, nil
end

local function findBestEggForHatching()
    local eggName, eggData = getBestEggData()
    if not eggName then return nil end
    
    local eggModel = nil
    local currentZone = MapCmds.GetCurrentZone()
    
    if currentZone then
        local zoneFolder = workspace:FindFirstChild("__THINGS")
        if zoneFolder then
            zoneFolder = zoneFolder:FindFirstChild("Eggs")
            if zoneFolder then
                for _, child in pairs(zoneFolder:GetChildren()) do
                    if child:IsA("Model") and child.Name:find(eggName) then
                        eggModel = child
                        break
                    end
                end
            end
        end
    end
    
    return eggModel
end

local function teleportToEgg()
    local eggModel = findBestEggForHatching()
    local HRP = getHRP()
    
    if not HRP then 
        print("No HRP found for egg teleportation!")
        return false 
    end
    
    if eggModel then
        local eggPosition = nil
        if eggModel.PrimaryPart then
            eggPosition = eggModel.PrimaryPart.Position
        elseif eggModel:FindFirstChild("HumanoidRootPart") then
            eggPosition = eggModel.HumanoidRootPart.Position
        elseif eggModel:IsA("Part") then
            eggPosition = eggModel.Position
        else
            -- Try to find any part in the model
            for _, child in pairs(eggModel:GetChildren()) do
                if child:IsA("Part") then
                    eggPosition = child.Position
                    break
                end
            end
        end
        
        if eggPosition then
            print("Teleporting directly to egg:", eggModel.Name, "at position:", eggPosition)
            HRP.Position = eggPosition + Vector3.new(0, 5, 0)
            task.wait(0.5)
            return true
        end
    end
    
    print("Egg not found or no valid position, using zone progression instead")
    return progressZone()
end

local function useInventoryItems(questType)
    local questPatterns = {
        ["comets_best"] = {inventory = "Misc", item = "Comet", action = "Comet_Spawn"},
        ["comets"] = {inventory = "Misc", item = "Comet", action = "Comet_Spawn"},
        ["coin_jars_best"] = {inventory = "Misc", item = "Basic Coin Jar", action = "CoinJar_Spawn"},
        ["coin_jars"] = {inventory = "Misc", item = "Basic Coin Jar", action = "CoinJar_Spawn"},
        ["lucky_blocks_best"] = {inventory = "Misc", item = "Lucky Block", action = "MiniLuckyBlock_Consume"},
        ["lucky_blocks"] = {inventory = "Misc", item = "Lucky Block", action = "MiniLuckyBlock_Consume"},
        ["pinatas_best"] = {inventory = "Misc", item = "Mini Pinata", action = "MiniPinata_Consume"},
        ["pinatas"] = {inventory = "Misc", item = "Mini Pinata", action = "MiniPinata_Consume"},
        ["flags"] = {inventory = "Misc", item = "Flag", action = "FlexibleFlags_Consume"},
    }
    
    local questPattern = questPatterns[questType]
    if not questPattern then return false end

    local isBest = string.find(questType, "_best")
    local needsPause = questType == "comets" or questType == "comets_best" or 
                      questType == "coin_jars" or questType == "coin_jars_best" or
                      questType == "lucky_blocks" or questType == "lucky_blocks_best" or
                      questType == "pinatas" or questType == "pinatas_best"
    
    if needsPause then
        pauseZoneProgression, pauseZoneBuying = true, true
    end

    for difficulty, quest in pairs(activeQuests) do
        if quest and quest.type == questType then
            if quest.completed then 
                if needsPause then pauseZoneProgression, pauseZoneBuying = false, false end
                return true 
            end
            
            local totalAmount = quest.amount or extractAmount(quest)
            local currentProgress = quest.progress or 0
            local neededAmount = totalAmount - currentProgress
            
            if neededAmount <= 0 then
                print("Quest already completed!")
                if needsPause then pauseZoneProgression, pauseZoneBuying = false, false end
                return true
            end
            
            print("Need", neededAmount, "more", questType, "items (", currentProgress, "/", totalAmount, ")")
            
            local availableItems = 0
            if Save and Save.Inventory and Save.Inventory[questPattern.inventory] then
                for UID, data in pairs(Save.Inventory[questPattern.inventory]) do
                    if data and data.id and string.find(data.id, questPattern.item) and data._am and data._am > 0 then
                        availableItems = availableItems + data._am
                    end
                end
            end
            
            if availableItems < neededAmount then
                print("Skipping", questType, "quest - need", neededAmount, "but only have", availableItems, "(", currentProgress, "/", totalAmount, ")")
                if needsPause then pauseZoneProgression, pauseZoneBuying = false, false end
                return false
            end
            
            if isBest then moveToMaxZone() end
            
            local usedAmount = 0
            for UID, data in pairs(Save.Inventory[questPattern.inventory]) do
                if usedAmount >= neededAmount then break end
                if data and data.id and string.find(data.id, questPattern.item) and data._am and data._am > 0 then
                    local useAmount = math.min(data._am, neededAmount - usedAmount)
                    for i = 1, useAmount do
                        if questPattern.action == "FlexibleFlags_Consume" then
                            Network.Invoke(questPattern.action, data.id, UID)
                        else
                            Network.Invoke(questPattern.action, UID)
                        end
                        task.wait(0.1)
                    end
                    usedAmount = usedAmount + useAmount
                end
            end
            task.wait(1)
            
            local questFinished = usedAmount >= neededAmount
            
            if needsPause then
                local stillActive = false
                for difficulty, quest in pairs(activeQuests) do
                    if quest and quest.type == questType and not quest.completed then
                        stillActive = true
                        break
                    end
                end
                
                if not stillActive then
                    pauseZoneProgression, pauseZoneBuying = false, false
                end
            end
            
            return questFinished
        end
    end
    
    if needsPause then
        pauseZoneProgression, pauseZoneBuying = false, false
    end
    return false
end

local function useTierPotions()
    for difficulty, quest in pairs(activeQuests) do
        if quest and quest.type == "tier_potions" then
            if quest.completed then return true end

            local totalAmount = quest.amount or extractAmount(quest)
            local currentProgress = quest.progress or 0
            local neededAmount = totalAmount - currentProgress
            
            local targetTier = nil
            for goalIndex, goalData in pairs(Save.Goals) do
                if goalData and goalData.Type == 34 then
                    if goalData.Tier then
                        targetTier = goalData.Tier
                    elseif goalData.RequiredTier then
                        targetTier = goalData.RequiredTier
                    else
                        targetTier = 1
                    end
                    break
                end
            end
            
            if not targetTier then 
                print("Could not determine target tier for tier_potions quest")
                return false 
            end
            
            if neededAmount <= 0 then
                print("Quest already completed!")
                return true
            end
            
            print("Need", neededAmount, "more items for tier_potions (", currentProgress, "/", totalAmount, ")")

            local availablePotions = 0
            for UID, data in pairs(Save.Inventory.Potion) do
                if data and data.tn and data._am and data.tn >= targetTier and data._am > 0 then
                    availablePotions = availablePotions + data._am
                end
            end
            
            if availablePotions < neededAmount then
                print("Skipping tier potions quest - need", neededAmount, "tier", targetTier, "potions but only have", availablePotions, "(", currentProgress, "/", totalAmount, ")")
                return false
            end

            local consumedCount = 0
            for UID, data in pairs(Save.Inventory.Potion) do
                if consumedCount >= neededAmount then break end
                if data and data.tn and data._am and data.tn >= targetTier and data._am > 0 then
                    local canConsume = math.min(data._am, neededAmount - consumedCount)
                    if canConsume > 0 then
                        game:GetService("ReplicatedStorage"):WaitForChild("Network"):WaitForChild("Potions: Consume"):FireServer(UID, canConsume)
                        consumedCount = consumedCount + canConsume
                        task.wait(0.1)
                    end
                end
            end
            task.wait(1)
            return consumedCount >= neededAmount
        end
    end
    return false
end

local function craftMachineItems(questType, machineCFrame, inventory, craftCosts)
    pauseZoneProgression = true
    local HRP = getHRP()
    if not HRP then 
        pauseZoneProgression = false
        return false 
    end
    
    for difficulty, quest in pairs(activeQuests) do
        if quest and quest.type == questType then
            local totalAmount = quest.amount or extractAmount(quest)
            local currentProgress = quest.progress or 0
            local neededAmount = totalAmount - currentProgress
            local canCompleteQuest = false
            local tempCraftedCount = 0
            
            print("Quest needs", neededAmount, "more items (", currentProgress, "/", totalAmount, ")")
            
            for UID, data in pairs(Save.Inventory[inventory]) do
                if tempCraftedCount >= neededAmount then canCompleteQuest = true break end
                if data and data.tn and data._am then
                    local craftCost = craftCosts[data.tn] or 0
                    if craftCost > 0 and data._am >= craftCost then
                        local canCraftFromStack = math.floor(data._am / craftCost)
                        tempCraftedCount = tempCraftedCount + math.min(canCraftFromStack, neededAmount - tempCraftedCount)
                    end
                end
            end
            
            if not canCompleteQuest then
                print("Skipping", questType, "quest - not enough materials to craft", neededAmount, "items")
                pauseZoneProgression = false
                return false 
            end
            break
        end
    end
    
    HRP.CFrame = machineCFrame
    task.wait(1)
    
    while true do
        local questActive = false
        for difficulty, quest in pairs(activeQuests) do
            if quest and quest.type == questType then
                questActive = true
                if quest.completed then
                    pauseZoneProgression = false
                    return true
                end
                break
            end
        end
        
        if not questActive then break end
        
        local HRP = getHRP()
        if not HRP then 
            pauseZoneProgression = false
            return false 
        end
        
        local distanceToMachine = (HRP.Position - machineCFrame.Position).Magnitude
        if distanceToMachine > 2 then
            print("Too far from machine, teleporting back - distance:", math.floor(distanceToMachine))
            HRP.CFrame = machineCFrame
            task.wait(1)
        end
        
        local questFound = false
        for difficulty, quest in pairs(activeQuests) do
            if quest and quest.type == questType then
                questFound = true
                local totalAmount = quest.amount or extractAmount(quest)
                local currentProgress = quest.progress or 0
                local neededAmount = totalAmount - currentProgress

                local craftedTotal = 0
                for UID, data in pairs(Save.Inventory[inventory]) do
                    if craftedTotal >= neededAmount then break end
                    if data and data.tn and data._am then
                        local craftCost = craftCosts[data.tn] or 0
                        if craftCost > 0 and data._am >= craftCost then
                            local canCraft = math.floor(data._am / craftCost)
                            local craftAmount = math.min(canCraft, neededAmount - craftedTotal)
                            if craftAmount > 0 then
                                local machineAction = questType == "collect_enchants" and "UpgradeEnchantsMachine_Activate" or "UpgradePotionsMachine_Activate"
                                Network.Invoke(machineAction, UID, craftAmount)
                                craftedTotal = craftedTotal + craftAmount
                                print("Crafted", craftAmount, "items, total:", craftedTotal, "/", neededAmount)
                                task.wait(1.5)
                            end
                        end
                    end
                end
                break
            end
        end
        
        if not questFound then break end
        task.wait(2)
    end
    
    pauseZoneProgression = false
    
    for difficulty, quest in pairs(activeQuests) do
        if quest and quest.type == questType then
            return quest.completed
        end
    end
    return false
end

local function craftEnchants()
    local enchantMachineCFrame = CFrame.new(914.696777, 13.561554, 481.951569, -0.999849796, 0, -0.0173500739, 0, 1, 0, 0.0173500739, 0, -0.999849796)
    return craftMachineItems("collect_enchants", enchantMachineCFrame, "Enchant", {[1] = 5, [2] = 5, [3] = 5, [4] = 7})
end

local function craftPotions()
    local potionMachineCFrame = CFrame.new(531.810059, 13.5644913, 325.669403, -0.0173809528, 0, 0.999849021, 0, 1, 0, -0.999849021, 0, -0.0173809528)
    return craftMachineItems("collect_potions", potionMachineCFrame, "Potion", {[1] = 3, [2] = 3, [3] = 4, [4] = 5})
end

local function hatchBestEggs(amountToHatch)
    pauseZoneProgression, pauseZoneBuying = true, true
    
    local questActive = false
    local currentQuestText = nil
    for difficulty, quest in pairs(activeQuests) do
        if quest and quest.type == "hatch_best" then
            questActive = true
            currentQuestText = quest.text
            if quest.completed then
                pauseZoneProgression, pauseZoneBuying = false, false
                return true
            end
            break
        end
    end

    local neededAmountForQuest = 0
    if questActive then
        for difficulty, quest in pairs(activeQuests) do
            if quest and quest.type == "hatch_best" then
                local totalAmount = quest.amount or extractAmount(quest)
                local currentProgress = quest.progress or 0
                neededAmountForQuest = totalAmount - currentProgress
                print("Need", neededAmountForQuest, "more best eggs (", currentProgress, "/", totalAmount, ")")
                break
            end
        end
    end
    
    local eggsToHatch = amountToHatch or neededAmountForQuest

    if eggsToHatch <= 0 then
        print("Best egg hatching quest already completed!")
        pauseZoneProgression, pauseZoneBuying = false, false
        return true
    end

    teleportToEgg()
    task.wait(1)

    local eggName, bestEggData = getBestEggData()
    if not eggName then
        pauseZoneProgression, pauseZoneBuying = false, false
        return false
    end

    local maxHatch = EggCmds.GetMaxHatch()
    local hatchedTotal = 0
    local lastProgress = 0
    local noProgressAttempts = 0
    local atEggPosition = true
    
    -- Get initial progress
    for difficulty, quest in pairs(activeQuests) do
        if quest and quest.type == "hatch_best" then
            lastProgress = quest.progress or 0
            break
        end
    end
    
    for i = 1, math.ceil(eggsToHatch / maxHatch) do
        if hatchedTotal >= eggsToHatch then break end
        
        local currentHatch = math.min(maxHatch, eggsToHatch - hatchedTotal)
        if currentHatch > 0 then
            Network.Invoke("Eggs_RequestPurchase", eggName, currentHatch)
            hatchedTotal = hatchedTotal + currentHatch
            task.wait(0.5)
            
            -- Check if progress increased
            local currentProgress = 0
            for difficulty, quest in pairs(activeQuests) do
                if quest and quest.type == "hatch_best" then
                    currentProgress = quest.progress or 0
                    break
                end
            end
            
            if currentProgress <= lastProgress then
                noProgressAttempts = noProgressAttempts + 1
                print("No progress detected, attempt", noProgressAttempts, "/5")
                
                if noProgressAttempts >= 5 and atEggPosition then
                    print("No progress after 5 attempts at egg, moving to zone center")
                    progressZone()
                    atEggPosition = false
                    task.wait(2)
                end
            else
                noProgressAttempts = 0
                lastProgress = currentProgress
            end
        end
    end
    
    task.wait(1)
    local questFinished = hatchedTotal >= eggsToHatch
    
    local stillActive = false
    for difficulty, quest in pairs(activeQuests) do
        if quest and quest.type == "hatch_best" and not quest.completed then
            stillActive = true
            break
        end
    end
    
    if not stillActive then
        pauseZoneProgression, pauseZoneBuying = false, false
    end
    
    task.wait(3)
    return questFinished
end

local function makeGoldenPets(amountToCraft)
    pauseZoneProgression, pauseZoneBuying = true, true
    
    local questActive = false
    local currentQuestText = nil
    for difficulty, quest in pairs(activeQuests) do
        if quest and quest.type == "golden_pets" then
            questActive = true
            currentQuestText = quest.text
            if quest.completed then
                pauseZoneProgression, pauseZoneBuying = false, false
                return true
            end
            break
        end
    end

    local neededAmountForQuest = 0
    if questActive then
        for difficulty, quest in pairs(activeQuests) do
            if quest and quest.type == "golden_pets" then
                local totalAmount = quest.amount or extractAmount(quest)
                local currentProgress = quest.progress or 0
                neededAmountForQuest = totalAmount - currentProgress
                print("Need", neededAmountForQuest, "more golden pets (", currentProgress, "/", totalAmount, ")")
                break
            end
        end
    end
    
    local petsToCraft = amountToCraft or neededAmountForQuest

    if petsToCraft <= 0 then
        print("Golden pets quest already completed!")
        pauseZoneProgression, pauseZoneBuying = false, false
        return true
    end

    local neededNormalPets = petsToCraft * 10
    
    local eggName, bestEggData = getBestEggData()
    if not bestEggData or not bestEggData.pets then
        pauseZoneProgression, pauseZoneBuying = false, false
        return false
    end
    
    local eligiblePetsInInventory = getEligiblePetsInInventory(nil, 1)
    local canCraft = false
    
    for _, petInfo in ipairs(bestEggData.pets) do
        local petNameFromEgg = petInfo[1]
        if eligiblePetsInInventory[petNameFromEgg] and eligiblePetsInInventory[petNameFromEgg].count >= neededNormalPets then
            canCraft = true
            break
        end
    end
    
    if not canCraft then
        print("Need", neededNormalPets, "normal pets but don't have enough - will try to hatch more (need", petsToCraft, "golden pets)")
    end

    progressZone()
    task.wait(1)

    local craftingUID = nil
    local craftingPetName = nil
    local craftingPetData = nil
    
    for _, petInfo in ipairs(bestEggData.pets) do
        local petNameFromEgg = petInfo[1]
        if eligiblePetsInInventory[petNameFromEgg] and eligiblePetsInInventory[petNameFromEgg].count >= neededNormalPets then
            craftingPetName = petNameFromEgg
            
            local bestUID = nil
            local bestAmount = 0
            
            for _, uid in ipairs(eligiblePetsInInventory[petNameFromEgg].uids) do
                local petData = Save.Inventory.Pet[uid]
                if petData and petData._am and petData._am > bestAmount then
                    bestUID = uid
                    bestAmount = petData._am
                    craftingPetData = petData
                end
            end
            
            if bestUID and bestAmount >= neededNormalPets then
                craftingUID = bestUID
                break
            end
        end
    end

    if not craftingUID then
        local hatchSuccess = hatchBestEggs(neededNormalPets)
        if not hatchSuccess then
            pauseZoneProgression, pauseZoneBuying = false, false
            return false
        end
        
        eligiblePetsInInventory = getEligiblePetsInInventory(nil, 1)
        for _, petInfo in ipairs(bestEggData.pets) do
            local petNameFromEgg = petInfo[1]
            if eligiblePetsInInventory[petNameFromEgg] and eligiblePetsInInventory[petNameFromEgg].count >= neededNormalPets then
                craftingPetName = petNameFromEgg
                
                local bestUID = nil
                local bestAmount = 0
                
                for _, uid in ipairs(eligiblePetsInInventory[petNameFromEgg].uids) do
                    local petData = Save.Inventory.Pet[uid]
                    if petData and petData._am and petData._am > bestAmount then
                        bestUID = uid
                        bestAmount = petData._am
                        craftingPetData = petData
                    end
                end
                
                if bestUID and bestAmount >= neededNormalPets then
                    craftingUID = bestUID
                    break
                end
            end
        end
        
        if not craftingUID then
            pauseZoneProgression, pauseZoneBuying = false, false
            return false
        end
    end

    local HRP = getHRP()
    if not HRP then
        pauseZoneProgression, pauseZoneBuying = false, false
        return false
    end

    HRP.CFrame = GOLD_MACHINE_CFRAME
    task.wait(1)

    Network.Invoke("GoldMachine_Activate", craftingUID, petsToCraft)
    task.wait(2)

    local questFinished = true
    
    local stillActive = false
    for difficulty, quest in pairs(activeQuests) do
        if quest and quest.type == "golden_pets" and not quest.completed then
            stillActive = true
            break
        end
    end
    
    if not stillActive then
        pauseZoneProgression, pauseZoneBuying = false, false
    end
    
    task.wait(3)
    return questFinished
end

local function makeRainbowPets()
    pauseZoneProgression, pauseZoneBuying = true, true

    for difficulty, quest in pairs(activeQuests) do
        if quest and quest.type == "rainbow_pets" then
            if quest.completed then
                pauseZoneProgression, pauseZoneBuying = false, false
                return true
            end

            local totalAmount = quest.amount or extractAmount(quest)
            local currentProgress = quest.progress or 0
            local neededRainbowPets = totalAmount - currentProgress
            
            if neededRainbowPets <= 0 then
                print("Rainbow pets quest already completed!")
                pauseZoneProgression, pauseZoneBuying = false, false
                return true
            end
            
            print("Need", neededRainbowPets, "more rainbow pets (", currentProgress, "/", totalAmount, ")")
            local neededGoldenPets = neededRainbowPets * 10

            local eggName, bestEggData = getBestEggData()
            if not bestEggData or not bestEggData.pets then
                pauseZoneProgression, pauseZoneBuying = false, false
                return false
            end

            local eligibleGoldenPetsInInventory = getEligiblePetsInInventory(1, 2)
            local totalAvailableGolden = 0
            for _, data in pairs(eligibleGoldenPetsInInventory) do
                totalAvailableGolden = totalAvailableGolden + data.count
            end

            if totalAvailableGolden < neededGoldenPets then
                print("Need", neededGoldenPets, "golden pets but only have", totalAvailableGolden, "- making more golden pets first (need", neededRainbowPets, "rainbow pets)")
                local goldenPetsNeeded = math.ceil((neededGoldenPets - totalAvailableGolden) / 10) * 10
                local goldenSuccess = makeGoldenPets(goldenPetsNeeded)
                if not goldenSuccess then
                    print("Failed to make golden pets for rainbow quest")
                    pauseZoneProgression, pauseZoneBuying = false, false
                    return false
                end
                
                eligibleGoldenPetsInInventory = getEligiblePetsInInventory(1, 2)
                totalAvailableGolden = 0
                for _, data in pairs(eligibleGoldenPetsInInventory) do
                    totalAvailableGolden = totalAvailableGolden + data.count
                end
                
                if totalAvailableGolden < neededGoldenPets then
                    print("Still don't have enough golden pets after crafting")
                    pauseZoneProgression, pauseZoneBuying = false, false
                    return false
                end
            end

            progressZone()
            task.wait(1)

            local craftingUID = nil
            local craftingPetName = nil
            
            for _, petInfo in ipairs(bestEggData.pets) do
                local petNameFromEgg = petInfo[1]
                if eligibleGoldenPetsInInventory[petNameFromEgg] then
                    local bestUID = nil
                    local bestAmount = 0
                    
                    for _, uid in ipairs(eligibleGoldenPetsInInventory[petNameFromEgg].uids) do
                        local petData = Save.Inventory.Pet[uid]
                        if petData and petData._am and petData._am > bestAmount then
                            bestUID = uid
                            bestAmount = petData._am
                        end
                    end
                    
                    if bestUID and bestAmount >= neededGoldenPets then
                        craftingUID = bestUID
                        craftingPetName = petNameFromEgg
                        break
                    end
                end
            end

            if not craftingUID then
                pauseZoneProgression, pauseZoneBuying = false, false
                return false
            end

            local HRP = getHRP()
            if not HRP then
                pauseZoneProgression, pauseZoneBuying = false, false
                return false
            end

            HRP.CFrame = RAINBOW_MACHINE_CFRAME
            task.wait(1)

            Network.Invoke("RainbowMachine_Activate", craftingUID, neededRainbowPets)
            task.wait(2)

            local questFinished = true
            
            local stillActive = false
            for difficulty, quest in pairs(activeQuests) do
                if quest and quest.type == "rainbow_pets" and not quest.completed then
                    stillActive = true
                    break
                end
            end
            
            if not stillActive then
                pauseZoneProgression, pauseZoneBuying = false, false
            end
            
            task.wait(3)
            return questFinished
        end
    end
    pauseZoneProgression, pauseZoneBuying = false, false
    return false
end

local function hatchEggs(amountToHatch)
    pauseZoneProgression, pauseZoneBuying = true, true
    
    local questActive = false
    local currentQuestText = nil
    for difficulty, quest in pairs(activeQuests) do
        if quest and quest.type == "hatch" then
            questActive = true
            currentQuestText = quest.text
            if quest.completed then
                pauseZoneProgression, pauseZoneBuying = false, false
                return true
            end
            break
        end
    end

    local neededAmountForQuest = 0
    if questActive then
        for difficulty, quest in pairs(activeQuests) do
            if quest and quest.type == "hatch" then
                local totalAmount = quest.amount or extractAmount(quest)
                local currentProgress = quest.progress or 0
                neededAmountForQuest = totalAmount - currentProgress
                print("Need", neededAmountForQuest, "more eggs (", currentProgress, "/", totalAmount, ")")
                break
            end
        end
    end
    
    local eggsToHatch = amountToHatch or neededAmountForQuest

    if eggsToHatch <= 0 then
        print("Egg hatching quest already completed!")
        pauseZoneProgression, pauseZoneBuying = false, false
        return true
    end

    teleportToEgg()
    task.wait(1)

    local eggName, bestEggData = getBestEggData()
    if not eggName then
        pauseZoneProgression, pauseZoneBuying = false, false
        return false
    end

    local maxHatch = EggCmds.GetMaxHatch()
    local hatchedTotal = 0
    local lastProgress = 0
    local noProgressAttempts = 0
    local atEggPosition = true
    
    -- Get initial progress
    for difficulty, quest in pairs(activeQuests) do
        if quest and quest.type == "hatch" then
            lastProgress = quest.progress or 0
            break
        end
    end
    
    for i = 1, math.ceil(eggsToHatch / maxHatch) do
        if hatchedTotal >= eggsToHatch then break end
        
        local currentHatch = math.min(maxHatch, eggsToHatch - hatchedTotal)
        if currentHatch > 0 then
            Network.Invoke("Eggs_RequestPurchase", eggName, currentHatch)
            hatchedTotal = hatchedTotal + currentHatch
            task.wait(0.5)
            
            -- Check if progress increased
            local currentProgress = 0
            for difficulty, quest in pairs(activeQuests) do
                if quest and quest.type == "hatch" then
                    currentProgress = quest.progress or 0
                    break
                end
            end
            
            if currentProgress <= lastProgress then
                noProgressAttempts = noProgressAttempts + 1
                print("No progress detected, attempt", noProgressAttempts, "/5")
                
                if noProgressAttempts >= 5 and atEggPosition then
                    print("No progress after 5 attempts at egg, moving to zone center")
                    progressZone()
                    atEggPosition = false
                    task.wait(2)
                end
            else
                noProgressAttempts = 0
                lastProgress = currentProgress
            end
        end
    end
    
    task.wait(1)
    local questFinished = hatchedTotal >= eggsToHatch
    
    local stillActive = false
    for difficulty, quest in pairs(activeQuests) do
        if quest and quest.type == "hatch" and not quest.completed then
            stillActive = true
            break
        end
    end
    
    if not stillActive then
        pauseZoneProgression, pauseZoneBuying = false, false
    end
    
    return questFinished
end

local function useFruits()
    for difficulty, quest in pairs(activeQuests) do
        if quest and quest.type == "fruits" then
            if quest.completed then return true end
            
            local totalAmount = quest.amount or extractAmount(quest)
            local currentProgress = quest.progress or 0
            local neededAmount = totalAmount - currentProgress
            
            if neededAmount <= 0 then
                print("Fruits quest already completed!")
                return true
            end
            
            print("Need", neededAmount, "more fruits (", currentProgress, "/", totalAmount, ")")
            
            local availableFruits = 0
            if Save and Save.Inventory and Save.Inventory.Fruit then
                for i, v in pairs(Save.Inventory.Fruit) do
                    if v.id == "Apple" or v.id == "Banana" or v.id == "Rainbow" or v.id == "Orange" or v.id == "Pineapple" or v.id == "Watermelon" then
                        if v._am and v._am > 0 then
                            availableFruits = availableFruits + v._am
                        end
                    end
                end
            end
            
            if availableFruits < neededAmount then
                print("Skipping fruits quest - need", neededAmount, "but only have", availableFruits, "(", currentProgress, "/", totalAmount, ")")
                return false
            end
            
            local usedAmount = 0
            if Save and Save.Inventory and Save.Inventory.Fruit then
                for i, v in pairs(Save.Inventory.Fruit) do
                    if usedAmount >= neededAmount then break end
                    if v.id == "Apple" or v.id == "Banana" or v.id == "Rainbow" or v.id == "Orange" or v.id == "Pineapple" or v.id == "Watermelon" then
                        if v._am and v._am > 0 then
                            local useAmount = math.min(v._am, neededAmount - usedAmount)
                            for j = 1, useAmount do
                                Network.Fire("Fruits: Consume", i, 1)
                                usedAmount = usedAmount + 1
                                task.wait(0.1)
                            end
                        end
                    end
                end
            end
            
            task.wait(1)
            return quest.completed or usedAmount >= neededAmount
        end
    end
    return false
end

local questFunctions = {
    ["flags"] = function() return useInventoryItems("flags") end,
    ["collect_enchants"] = craftEnchants,
    ["collect_potions"] = craftPotions,
    ["comets"] = function() return useInventoryItems("comets") end,
    ["comets_best"] = function() return useInventoryItems("comets_best") end,
    ["coin_jars"] = function() return useInventoryItems("coin_jars") end,
    ["coin_jars_best"] = function() return useInventoryItems("coin_jars_best") end,
    ["lucky_blocks"] = function() return useInventoryItems("lucky_blocks") end,
    ["lucky_blocks_best"] = function() return useInventoryItems("lucky_blocks_best") end,
    ["pinatas"] = function() return useInventoryItems("pinatas") end,
    ["pinatas_best"] = function() return useInventoryItems("pinatas_best") end,
    ["hatch"] = hatchEggs,
    ["hatch_best"] = hatchBestEggs,
    ["golden_pets"] = makeGoldenPets,
    ["rainbow_pets"] = makeRainbowPets,
    ["tier_potions"] = useTierPotions,
    ["fruits"] = useFruits,
}

task.spawn(function()
    while true do
        if not pauseZoneBuying then
            local nextZone = ZoneCmds.GetNextZone()
            Network.Invoke("Zones_RequestPurchase", nextZone)
        end
        task.wait(5)
    end
end)

task.spawn(function()
    while true do
        for rankSlots = 1, 36 do
            Network.Fire("Ranks_ClaimReward", rankSlots)
            task.wait(0.1)
        end
        task.wait(5)
    end
end)

task.spawn(function()
    while true do 
        local PetslotsPurchased = Save.PetslotsPurchased
        local MaxSlots = RCmds.GetMaxPurchasableEquipSlots()
        
        if PetslotsPurchased == nil then 
            PetslotsPurchased = 1 
        end
        
        for i = PetslotsPurchased + 1, MaxSlots do 
            Network.Invoke("EquipSlotsMachine_RequestPurchase", i)
        end
        
        task.wait(5)
    end
end)

task.spawn(function()
    while true do 
        local CurrentEggSlots = Save.EggHatchCount
        local MaxEggSlots = RCmds.GetMaxPurchasableEggSlots()
        
        if CurrentEggSlots == nil then
            CurrentEggSlots = 1
        end
        
        for i = CurrentEggSlots + 1, MaxEggSlots do 
            Network.Invoke("EggHatchSlotsMachine_RequestPurchase", i)
        end
        
        task.wait(5)
    end
end)

function executeQuests()
    local difficultyOrder = {"Extreme", "Hard", "Medium", "Easy"}
    local anyQuestAttempted = false
    
    for _, difficulty in ipairs(difficultyOrder) do
        local quest = activeQuests[difficulty]
        if quest and questFunctions[quest.type] then
            anyQuestAttempted = true
            print("Attempting quest:", quest.type, "(" .. quest.text .. ")")
            local success = questFunctions[quest.type]()
            if success then
                print("Quest completed successfully:", quest.type)
                return true
            else
                print("Quest failed, trying next available quest:", quest.type)
            end
        end
    end
    
    if anyQuestAttempted then
        print("All available quests failed")
    else
        print("No quests available to attempt")
    end
    return false
end

task.spawn(function()
    local function updateActiveQuests()
        local newActiveQuests = {}
        
        for goalIndex, goalData in pairs(Save.Goals) do
            if goalData and goalData.Type and goalData.Amount and goalData.Progress then
                local questType = QUEST_TYPES[goalData.Type]
                if questType then
                    local difficulty = "Easy"
                    if goalData.Stars >= 4 then
                        difficulty = "Extreme"
                    elseif goalData.Stars >= 3 then
                        difficulty = "Hard"  
                    elseif goalData.Stars >= 2 then
                        difficulty = "Medium"
                    end
                    
                    local questText = questType .. " " .. goalData.Amount .. " (Progress: " .. goalData.Progress .. "/" .. goalData.Amount .. ")"
                    if questType == "tier_potions" and goalData.Tier then
                        questText = "Use " .. goalData.Amount .. " Tier " .. goalData.Tier .. " potions (Progress: " .. goalData.Progress .. "/" .. goalData.Amount .. ")"
                    end
                    
                    newActiveQuests[difficulty] = {
                        type = questType, 
                        text = questText,
                        amount = goalData.Amount,
                        progress = goalData.Progress,
                        completed = goalData.Progress >= goalData.Amount,
                        goalData = goalData
                    }
                    
                    print("Active Quest:", questType, "- Progress:", goalData.Progress .. "/" .. goalData.Amount)
                end
            end
        end
        
        for questText in pairs(completedQuests) do
            local stillActive = false
            for _, quest in pairs(newActiveQuests) do
                if quest.text == questText then
                    stillActive = true
                    break
                end
            end
            if not stillActive then
                completedQuests[questText] = nil
            end
        end
        
        activeQuests = newActiveQuests
    end

    while true do
        updateActiveQuests()
        task.wait(2)
    end
end)

task.spawn(function()
    print("Script started!")
    
    while true do
        local maxOwnedZoneID = ZoneCmds.GetMaxOwnedZone()
        local currentZoneID = MapCmds.GetCurrentZone()
        
        if currentZoneID ~= maxOwnedZoneID then
            print("Not at max zone, progressing...")
            progressToMaxZone()
            task.wait(1)
        else
            print("At max zone, starting quest loop")
            break
        end
    end
    
    while true do
        print("Checking for quests...")
        local questCompleted = executeQuests()
        if questCompleted then
            print("Quest completed, progressing zone...")
            progressZone()
            task.wait(2)
        else
            print("No quest completed, trying to progress zone...")
            if progressZone() then
                task.wait(1)
            else
                print("No zone to progress to, waiting...")
                task.wait(3)
            end
        end
    end
end)