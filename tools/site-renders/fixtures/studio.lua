-- Actual addon controls and individually filtered components for the browser editor.
function RikRenderStudio()
    assert(RikUI.Studio.Open())
    RikRenderCenter(RikUIStudio)
end
function RikRenderStudioHandheld()
    RikRenderScreenState()
    assert(RikUI.Studio.Select("hud"))
    RikUI.Studio.Device="handheld"
    local review=assert(RikUI.Studio.Review());for _,c in ipairs(review.fit.conflicts) do print("FIT "..c.key.." "..c.reason)end
    assert(RikUI.Studio.Apply())
    if RikUIStudio then RikUIStudio:Hide() end
    assert(RikUI.Profile.presentation.hidden.bar4)
    assert(not RikUIBar_bar4:IsShown())
end
function RikRenderStudioAtlas(sample)
    RikRenderScreenState()
    if sample=="tot" then RikRenderUnitAlias("targettarget","player");RikUI.UnitFrames.Refresh() end
    if sample=="debuffs" then RikRenderAuras({{702,"Curse of Weakness",136138,120,harmful=true},{772,"Rend",132155,9,harmful=true},{172,"Corruption",136118,12,harmful=true}}) end
    RikRenderDurability({[1]=1},{[1]=45})
    RikUI.Profile.barFade={main=false,bar2=false,bar3=false,bar4=false,bar5=false};RikUI.Bars.Refresh()
    assert(RikUI.UnitFrames.Party.SetTest(true))
    assert(RikUI.UnitFrames.Raid.SetTest(true))
    RikRenderBagItems();RikUI.Bags.Holder:Show()
    if sample=="nameplates" then
        local first=RikRenderNameplates({{unit="target",screen={x=1024,y=552}},{screen={x=1184,y=624},notTarget=true,readers=RikRenderCreature("Young Wolf",1,30)}}, "RikRenderStudioPlates",724,446,600,260)
        local record=first:CreateFontString("RikRenderStudioGeometrynameplates","OVERLAY","GameFontNormal");record:SetText("STUDIO_GROUP nameplates 724 446 600 260");record:Hide();return
    end
    local key=sample=="questtrackerCollapsed" and "questtracker" or sample
    if sample=="questtrackerCollapsed" then
        RikUI.Profile.questtracker.collapsed=true;RikUI.QuestTracker.Refresh()
    end
    local group=assert(RikUI.Layout.Groups[key],"Unknown native preview group")
    local first=assert(group.frames[1]);if sample=="tot" then pcall(UnregisterStateDriver,first,"visibility") end;first:Show()
    RikUI.Profile.scale=1
    local w,h=first:GetSize()
    RikUI.Profile.positions[key]={point="BOTTOMLEFT",relativePoint="BOTTOMLEFT",x=(2048-w)/2,y=(1152-h)/2}
    RikUI.Layout.Apply();RikRenderResize(first);RikRenderRemeasure(first)
    -- Other groups can resize and settle during Apply; center the filtered native root last.
    RikRenderCenter(first,1);w,h=first:GetSize()
    local record=first:CreateFontString("RikRenderStudioGeometry"..sample,"OVERLAY","GameFontNormal")
    record:SetText(string.format("STUDIO_GROUP %s %.3f %.3f %.3f %.3f",sample,first:GetLeft(),first:GetBottom(),w,h));record:Hide()
end
