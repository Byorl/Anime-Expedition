--!nocheck
--[[
	Fishing minigame result-trust reproduction (PoC)
	Authorized security testing - Anime Expeditions (Summer Update build).

	Vulnerability
	-------------
	The fishing flow is: client casts (FISH_CAST_REEL: FireServer(waterPosition,
	holdSeconds)) -> server drives the "Waiting" -> "Reeling" stages and
	replicates them through FISHING_STATE_CHANGED -> the client answers the reel
	minigame with FISHING_RESULT:FireServer(successBoolean)
	(LocalScript/0287 ClientFishingHandler, setStage "Reeling" branch).

	The minigame outcome is a client-controlled boolean. The server grants the
	catch and fishing rank EXP (FishingRanks.RarityToExp: Rare 6, Epic 10,
	Legendary 20, Mythic 40, Secret 100) on that boolean. Reporting true without
	playing the minigame is indistinguishable on the wire from a legitimate
	SkipMinigame result, which the same code path sends legitimately.

	Impact: fast fishing-rank progression, and rank directly sets the daily
	"+250 event currency per non-event win" cap (FishingRanks.Ranks:
	Veteran 5,000 / Master 7,500 / Grandmaster 10,000 - the AE_CAP_RANK values).
	The cap itself is enforced server-side and is NOT bypassable from the
	client; raising the rank is the legitimate-config route to a bigger cap.

	Usage: equip a fishing rod and stand at water in the Summer event lobby,
	then run. Stops after MAX_CATCHES or when _G.EXPLOIT_POC_STOP is true.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local CONFIG = {
	MAX_CATCHES = 100, -- safety cap; raise for longer sessions
	BITE_TIMEOUT = 30, -- recast if the fish never bites
	CAST_COOLDOWN = 0.5, -- seconds between cast attempts
	HOLD_SECONDS = 0.35, -- reported rod hold duration
	WATER_RANGE = 60, -- studs to search for tagged Water
}

local Nodes = require(ReplicatedStorage:WaitForChild("Nodes"))
local ItemUtils = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ItemUtils"))

local localPlayer = Players.LocalPlayer
local running = true
local catches = 0

local function log(message: string)
	print(("[FishPoC %05.1f] %s"):format(os.clock(), message))
end

local stage = "Idle"
local stageParams = nil

Nodes.FISHING_STATE_CHANGED:Connect(function(params, path, value, old)
	if type(path) == "table" and path[2] == "Stage" then
		stage = value
		stageParams = params
	end
end)

local function findWaterPosition()
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return nil
	end
	local nearest, nearestDistance = nil, CONFIG.WATER_RANGE
	for _, part in CollectionService:GetTagged("Water") do
		if part:IsA("BasePart") then
			local distance = (part.Position - root.Position).Magnitude
			if distance < nearestDistance then
				nearest = part.Position
				nearestDistance = distance
			end
		end
	end
	return nearest
end

local function castAt(waterPosition)
	local character = localPlayer.Character
	local head = character and character:FindFirstChild("Head")
	if not head then
		return false
	end
	local ok = pcall(function()
		Nodes.FISH_CAST_REEL:FireServer(waterPosition, CONFIG.HOLD_SECONDS)
	end)
	return ok
end

local function waitForStage(target, timeout)
	local deadline = os.clock() + timeout
	while running and os.clock() < deadline do
		if stage == target then
			return true
		end
		task.wait(0.05)
	end
	return false
end

log("PoC loaded; equip a rod and stand at water if you have not already")

while running and catches < CONFIG.MAX_CATCHES do
	if _G.EXPLOIT_POC_STOP == true then
		running = false
		break
	end

	local waterPosition = findWaterPosition()
	if not waterPosition then
		log(("no tagged Water within %d studs; move closer to water"):format(CONFIG.WATER_RANGE))
		task.wait(2)
		continue
	end

	if stage ~= "Idle" then
		-- A previous cycle may still be mid-flight; wait it out.
		waitForStage("Idle", CONFIG.BITE_TIMEOUT)
	end

	if not castAt(waterPosition) then
		log("cast failed (no character?)")
		task.wait(1)
		continue
	end
	log("cast sent")

	-- The server times the bite; when it replicates the Reeling stage the
	-- legitimate client starts the minigame. We answer immediately instead.
	local bit = waitForStage("Reeling", CONFIG.BITE_TIMEOUT)
	if not bit then
		log("no bite before timeout; recasting")
		continue
	end

	local skipFlag = stageParams and stageParams.Parameters and stageParams.Parameters.SkipMinigame
	pcall(function()
		Nodes.FISHING_RESULT:FireServer(true)
	end)
	log(("reported minigame success (legit skip flag present: %s)"):format(tostring(skipFlag == true)))
	catches += 1

	-- Let the server settle the catch and return to Idle before recasting.
	waitForStage("Idle", 10)
	task.wait(CONFIG.CAST_COOLDOWN)
end

log(("summary: %d forged-catch result(s) sent; each grants rank EXP and event currency server-side"):format(catches))
