-- Check actual shared fit and native preset output; this fixture draws no UI.
function RikRenderStudioCharacterClearance(native)
    local fit=assert(RikUI.Studio.Resolve())
    local zone=assert(fit.groups[1]);assert(zone.character and zone.key=="Character viewing area")
    local a=zone.rect;local screen=RikUI.Layout.Screen()
    assert(math.abs(a.x+a.width/2-screen.width/2)<0.01 and math.abs(a.y+a.height/2-screen.height/2)<0.01)
    for _,g in ipairs(fit.groups)do if RikUI.Studio.Draft.groups[g.key] and not g.floating then
        local b=g.rect
        assert(not(a.x<b.x+b.width and a.x+a.width>b.x and a.y<b.y+b.height and a.y+a.height>b.y),"Preset covers character: "..g.key)
        if native and RikUI.Layout.Groups[g.key] then
            local frame=RikUI.Layout.Groups[g.key].frames[1]
            local ratio=frame:GetEffectiveScale()/UIParent:GetEffectiveScale()
            assert(math.abs(frame:GetLeft()*ratio-b.x)<1 and math.abs(frame:GetBottom()*ratio-b.y)<1,"Applied native clearance differs: "..g.key)
        end
    end end
end
