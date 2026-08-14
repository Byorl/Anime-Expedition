local Catalog = rbxmk.loadFile("src/Core/CodeCatalog.lua")()()

local merged = Catalog.Merge({
	{Codes = {NEWCODE = {ActiveFrom = 100, ActiveUntil = 200}}},
	{Value = {Codes = {{Code = "SecondCode", ActiveUntil = 300}}}},
	{thirdcode = {Rewards = {{Asset = "Gem", Amount = 100}}}},
})
assert(merged.newcode and merged.newcode.Code == "NEWCODE", "wrapped static code was not discovered")
assert(merged.secondcode and merged.secondcode.Info.ActiveUntil == 300, "nested row code was not discovered")
assert(merged.thirdcode and merged.thirdcode.Code == "thirdcode", "direct live code map was not discovered")
assert(Catalog.IsActive(merged.newcode.Info, 150), "active code window was rejected")
assert(not Catalog.IsActive(merged.newcode.Info, 250), "expired code window was accepted")

local release = Catalog.ReleaseKey(merged.newcode.Info)
assert(not Catalog.CanAttempt({Status = "Accepted", ReleaseKey = release}, release, 150), "accepted code retried")
assert(Catalog.CanAttempt({Status = "Attempted", ReleaseKey = release, RetryAt = 149}, release, 150), "ambiguous code did not retry")
assert(not Catalog.CanAttempt({Status = "Attempted", ReleaseKey = release, RetryAt = 151}, release, 150), "retry cooldown was ignored")
assert(Catalog.CanAttempt({Status = "Rejected", ReleaseKey = "old"}, release, 150), "new code release was suppressed")

local status = Catalog.Classify({Success = false, Message = "Please wait before doing that again"})
assert(status == "Attempted", "transient server response was treated as terminal")
status = Catalog.Classify("Code has already been redeemed")
assert(status == "AlreadyRedeemed", "already redeemed response was not terminal")
status = Catalog.Classify("This code is expired")
assert(status == "Rejected", "expired response was not terminal")
status = Catalog.Classify({Success = true, Message = "Code redeemed"})
assert(status == "Accepted", "successful response was not accepted")

print("Code catalog tests passed")
