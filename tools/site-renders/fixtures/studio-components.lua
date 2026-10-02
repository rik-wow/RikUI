-- Missing browser samples use native frames and the same representative fixture readers.
function RikRenderStudioExtra(sample)
    RikRenderScreenState()
    local unit = ({casttarget="target",castfocus="focus",castpet="pet"})[sample]
    if unit then RikRenderCastAlias(unit) end
    if sample=="petframe" then
        pcall(UnregisterStateDriver,RikUIUnit_petframe,"visibility")
        RikUIUnit_petframe:Show()
    end
    if sample=="loot" then RikRenderItems();RikRenderLootCoins(4321);RikUI.Loot.Open() end
    local group=assert(RikUI.Layout.Groups[sample],"Missing native group")
    local first=assert(group.frames[1])
    first:Show();RikUI.Profile.scale=1;RikUI.Layout.Apply()
    RikRenderResize(first);RikRenderRemeasure(first);RikRenderCenter(first,1)
    if sample=="chat" then
        -- These are native UIParent siblings, not children of the layout holder.
        -- Reparent only for the simulator's filtered subtree; preserve every anchor.
        for _,name in ipairs({"ChatFrame1","GeneralDockManager","ChatFrame1Tab","ChatFrame1EditBox","RikUIChatStrip"}) do
            local frame=_G[name];if frame then frame:SetParent(first);frame:Show() end
        end
        if group.onApply then group.onApply(first) end
        ChatFrame1:SetAlpha(1)
        RikRenderResize(first);RikRenderRemeasure(first)
    end
    local w,h=first:GetSize()
    local record=first:CreateFontString("RikRenderExtraGeometry"..sample,"OVERLAY","GameFontNormal")
    record:SetText(string.format("STUDIO_GROUP %s %.3f %.3f %.3f %.3f",sample,first:GetLeft(),first:GetBottom(),w,h));record:Hide()
end

-- Assert positions after actual Apply, not merely after the shared data resolver.
function RikRenderStudioGeometryProof(scale)
    RikRenderScreenState()
    assert(RikUI.Studio.Select("centered"))
    RikUI.Studio.Draft.adjustments={scale=scale}
    local review=assert(RikUI.Studio.Review());assert(RikUI.Studio.Apply())
    if RikUIStudio then RikUIStudio:Hide() end
    for _,key in ipairs({"main","player","target","focus","chat","minimap","questtracker","micromenu","xpbar"}) do
        local expected
        for _,entry in ipairs(review.fit.groups)do if entry.key==key then expected=entry.rect end end
        local first=assert(RikUI.Layout.Groups[key].frames[1])
        local ratio=first:GetEffectiveScale()/UIParent:GetEffectiveScale()
        local x,y=first:GetLeft()*ratio,first:GetBottom()*ratio
        assert(expected and math.abs(x-expected.x)<1 and math.abs(y-expected.y)<1,
            string.format("Native/portable geometry mismatch %s: %.3f %.3f vs %.3f %.3f",key,x,y,expected.x,expected.y))
        print(string.format("NATIVE_FIT %s %.3f %.3f",key,x,y))
    end
end
