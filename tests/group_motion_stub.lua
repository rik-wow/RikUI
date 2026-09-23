-- Deterministic native animation lifecycle double; endpoints remain ordinary constants.
return function(owner)
    function owner:CreateAnimationGroup()
        if _G.RikTestAnimationsMissing then return nil end
        local group = { plays = 0, playing = false, alpha = {}, scripts = {} }
        function group:CreateAnimation() return self.alpha end
        function group:GetAnimations() return self.alpha end
        for _, key in ipairs({ "FromAlpha", "ToAlpha", "Duration" }) do
            group.alpha["Set" .. key] = function(self, value) self[key] = value end
        end
        function group:SetLooping(value) self.looping = value end
        function group:SetScript(name, callback) self.scripts[name] = callback end
        function group:Play() self.plays = self.plays + 1; self.playing = true end
        function group:Stop() self.playing = false end
        function group:IsPlaying() return self.playing end
        function group:Finish()
            self.playing = false
            if self.scripts.OnFinished then self.scripts.OnFinished(self) end
        end
        return group
    end
end
