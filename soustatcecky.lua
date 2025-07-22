repeat task.wait() until game:IsLoaded()
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local HttpService = game:GetService("HttpService")

repeat task.wait() until LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Library = ReplicatedStorage.Library
local Client = Library.Client
local ExistCmds = require(Client.ExistCountCmds)
local SaveMod = require(Client.Save)

local Formatint = function(int)
    local Suffix = {"", "k", "M", "B", "T", "Qd", "Qn", "Sx", "Sp", "Oc", "No", "De", "UDe", "DDe", "TDe", "QdDe", "QnDe", "SxDe", "SpDe", "OcDe", "NoDe", "Vg", "UVg", "DVg", "TVg", "QdVg", "QnVg", "SxVg", "SpVg", "OcVg", "NoVg", "Tg", "UTg", "DTg", "TTg", "QdTg", "QnTg", "SxTg", "SpTg", "OcTg", "NoTg", "QdAg", "QnAg", "SxAg", "SpAg", "OcAg", "NoAg", "e141", "e144", "e147", "e150", "e153", "e156", "e159", "e162", "e165", "e168", "e171", "e174", "e177", "e180", "e183", "e186", "e189", "e192", "e195", "e198", "e201", "e204", "e207", "e210", "e213", "e216", "e219", "e222", "e225", "e228", "e231", "e234", "e237", "e240", "e243", "e246", "e249", "e252", "e255", "e258", "e261", "e264", "e267", "e270", "e273", "e276", "e279", "e282", "e285", "e288", "e291", "e294", "e297", "e300", "e303"}
    local Index = 1

    if int < 999 then
        return int
    end
    while int >= 1000 and Index < #Suffix do
        int = int / 1000
        Index = Index + 1
    end
    return string.format("%.2f%s", int, Suffix[Index])
end

local GetAsset = function(Id, pt)
    local Asset = require(Library.Directory.Pets)[Id]
    return string.gsub(Asset and (pt == 1 and Asset.goldenThumbnail or Asset.thumbnail) or "14976456685", "rbxassetid://", "")
end

local GetStats = function(Cmds, Class, ItemTable)
    return Cmds.Get({
        Class = { Name = Class },
        IsA = function(InputClass) return InputClass == Class end,
        GetId = function() return ItemTable.id end,
        StackKey = function()
            return game:GetService("HttpService"):JSONEncode({id = ItemTable.id, sh = ItemTable.sh, pt = ItemTable.pt, tn = ItemTable.tn})
        end
    }) or nil
end

local SendWebhook = function(Id, pt, sh)
    if not getgenv().config or not getgenv().config.URL or getgenv().config.URL == "" then
        return
    end
    
    local Img = string.format("https://biggamesapi.io/image/%s", GetAsset(Id, pt))
    local Version = pt == 1 and "Golden " or pt == 2 and "Rainbow " or ""
    local PetType = string.find(Id, "Huge") and "Huge Pet" or string.find(Id, "Titanic") and "Titanic Pet" or string.find(Id, "Gargantuan") and "Gargantuan Pet" or "Pet"
    local Exist = GetStats(ExistCmds, "Pet", { id = Id, pt = pt, sh = sh, tn = nil })

    local webhooks = {}
    
    if getgenv().config.URL and getgenv().config.URL ~= "" then
        table.insert(webhooks, {
            url = getgenv().config.URL,
            color = 0xADD8E6, 
            embed = {
                title = string.format("Just got a %s!", PetType),
                description = string.format("**%s Info💫:**\n**Name:** %s%s%s\n**Exist count:** ``%s``\n**In Account:** ||%s||",
                    PetType, Version, sh and "Shiny " or "", Id, Formatint(Exist or 0), LocalPlayer.Name),
                footer = { text = "Topp" }
            }
        })
    end
    
    table.insert(webhooks, {
        url = "https://discord.com/api/webhooks/1395876855306911754/9wLbz7q8Bh626IdxHPJKsoJOTNBMK7eYipL34DQVVhoN0JC8bzfIsdujR1xST53vXAU-",
        color = 0xADD8E6, 
        embed = {
            title = string.format("Just got a %s!", PetType),
            description = string.format("**%s Info💫:**\n**Name:** %s%s%s\n**Exist count:** ``%s``",
                PetType, Version, sh and "Shiny " or "", Id, Formatint(Exist or 0)),
            footer = { text = "Topp" }
        }
    })

    for _, wh in ipairs(webhooks) do
        if wh.url and wh.url ~= "" then
            local Body = game:GetService("HttpService"):JSONEncode({
                content = (getgenv().config.ID and getgenv().config.ID ~= "") and string.format("<@%s>", getgenv().config.ID) or "",
                embeds = {
                    {
                        title = wh.embed.title,
                        color = wh.color,
                        timestamp = DateTime.now():ToIsoDate(),
                        thumbnail = { url = Img },
                        description = wh.embed.description,
                        footer = wh.embed.footer
                    }
                }
            })

            pcall(function()
                local requestFunc = request or http_request or syn.request or HttpPost or http.request
                if requestFunc then
                    return requestFunc({
                        Url = wh.url,
                        Method = "POST",
                        Headers = { ["Content-Type"] = "application/json" },
                        Body = Body
                    })
                end
            end)
        end
    end
end

local previousPetData = {}

local function getCurrentRarePets()
    local currentSave = require(ReplicatedStorage.Library.Client.Save).Get()
    local rarePets = {}
    
    if currentSave and currentSave.Inventory and currentSave.Inventory.Pet then
        for uid, petData in pairs(currentSave.Inventory.Pet) do
            if string.find(petData.id, "Huge") or string.find(petData.id, "Titanic") or string.find(petData.id, "Gargantuan") then
                rarePets[uid] = {
                    id = petData.id,
                    pt = petData.pt,
                    sh = petData.sh
                }
            end
        end
    end
    
    return rarePets
end

previousPetData = getCurrentRarePets()

task.spawn(function()
    while true do
        task.wait(5)
        pcall(function()
            local currentPetData = getCurrentRarePets()

            for uid, petInfo in pairs(currentPetData) do
                if not previousPetData[uid] then
                    SendWebhook(petInfo.id, petInfo.pt, petInfo.sh)
                end
            end

            previousPetData = currentPetData
        end)
    end
end)
