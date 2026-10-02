-- Exercise real guided pages and the real controls, never draw replacement widgets.
function RikRenderStudioPage(key)
    assert(RikUI.Studio.Select("centered"))
    RikRenderStudio()
    local state=key
    if key=="applied" or key=="conflict" then key="review" end
    if state=="conflict" then
        RikUI.Studio.Draft.adjustments={positions={main={point="BOTTOMLEFT",relativePoint="BOTTOMLEFT",x=500,y=100},player={point="BOTTOMLEFT",relativePoint="BOTTOMLEFT",x=500,y=100}}}
    end
    assert(RikUI.Studio.ShowPage(key))
    local c=RikUI.Studio.Controls
    if state=="applied" then
        c.apply:GetScript("OnClick")(c.apply)
        assert(RikUI.Studio.LastResult.status=="applied" and RikUIStudio.details:GetText():find("Setup applied"),"Successful apply is shown as an error")
    elseif state=="conflict" then assert(c.apply.disabled,"Conflicting layout can be applied") end
    assert(c.apply:IsVisible()==(key=="review"),"Apply leaked into another step")
    assert(c.exportLive:IsVisible()==(key=="share"),"Export leaked into another step")
    assert(c["move-Right"]:IsVisible()==(key=="layout"),"Layout controls leaked into another step")
end
function RikRenderStudioThemeReview()
    RikRenderStudioPage("look")
    local c=RikUI.Studio.Controls
    c["theme-ocean"]:GetScript("OnClick")(c["theme-ocean"])
    c["readability-readable"]:GetScript("OnClick")(c["readability-readable"])
    assert(c["theme-ocean"].isChosen and c["readability-readable"].isChosen,"Selected appearance is not highlighted")
    RikUI.Studio.Recipe("appearance")
    assert(RikUI.Studio.ShowPage("review"))
    assert(RikUI.Studio.Selected.appearance and not RikUI.Studio.Selected.hud)
    assert(RikUI.Studio.Draft.adjustments.theme.accent=="blue")
end
function RikRenderStudioEditUndo()
    RikRenderStudioPage("layout")
    local c=RikUI.Studio.Controls
    c["move-Right"]:GetScript("OnClick")(c["move-Right"])
    local moved=RikUI.SetupPack.Copy(RikUI.Studio.Draft.adjustments.positions)
    c.undo:GetScript("OnClick")(c.undo)
    assert(not RikUI.Studio.Draft.adjustments)
    c.redo:GetScript("OnClick")(c.redo)
    assert(RikUI.SetupPack.Equal(moved,RikUI.Studio.Draft.adjustments.positions))
    c.group:GetScript("OnClick")(c.group)
    local list=assert(c.group.choiceList)
    assert(list:IsShown() and #list.entries>10,"Frame chooser has no discoverable groups")
    list.choose(1)
    c.group:GetScript("OnClick")(c.group)
    assert(c.group.choiceList==list,"Reopening chooser leaked a new list")
    RikUIStudio:GetScript("OnKeyDown")(RikUIStudio,"ESCAPE")
    assert(not list:IsShown(),"Escape did not dismiss choices")
end
function RikRenderStudioPreviewJourney()
    RikRenderScreenState()
    RikRenderStudioPage("layout")
    local c=RikUI.Studio.Controls
    local source=RikUI.SetupPack.Copy(RikUI.Profile)
    c.tryOn:GetScript("OnClick")(c.tryOn)
    assert(not RikUIStudio:IsShown() and RikUI.Studio.PreviewBar:IsShown(),"Editor covers try-on")
    assert(RikUI.SetupPack.Equal(source,RikUI.Profile),"Try-on mutated settings")
    c.returnPreview:GetScript("OnClick")(c.returnPreview)
    assert(RikUIStudio:IsShown() and not RikUI.Studio.PreviewBar:IsShown(),"Return did not restore editor")
    c.tryOn:GetScript("OnClick")(c.tryOn)
    assert(not RikUIStudio:IsShown(),"Second try-on failed")
end
