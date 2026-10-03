-- Exercise real guided pages and the real controls, never draw replacement widgets.
function RikRenderStudioPage(key)
    assert(RikUI.Studio.Select("centered"))
    RikRenderStudio()
    local state=key
    if key=="applied" or key=="conflict" then key="review" end
    if key=="dropdown" or key=="groups" then key="layout" end
    if state=="conflict" then
        RikUI.Studio.Draft.adjustments={positions={main={point="BOTTOMLEFT",relativePoint="BOTTOMLEFT",x=500,y=100},player={point="BOTTOMLEFT",relativePoint="BOTTOMLEFT",x=500,y=100}}}
    end
    assert(RikUI.Studio.ShowPage(key))
    local c=RikUI.Studio.Controls
    if state=="applied" then
        assert(not c.apply.disabled, RikUIStudio.details:GetText())
        c.apply:GetScript("OnClick")(c.apply)
        assert(RikUI.Studio.LastResult, RikUIStudio.status:GetText())
        assert(RikUI.Studio.LastResult.status=="applied" and RikUIStudio.details:GetText():find("Setup applied"),"Successful apply is shown as an error")
    elseif state=="conflict" then assert(c.apply.disabled,"Conflicting layout can be applied") end
    assert(c.apply:IsVisible()==(key=="review"),"Apply leaked into another step")
    assert(c.exportLive:IsVisible()==(key=="share"),"Export leaked into another step")
    assert(c["move-Right"]:IsVisible()==(key=="layout"),"Layout controls leaked into another step")
    if state=="dropdown" or state=="groups" then
        local widget=state=="dropdown" and c.device or c.group
        widget:GetScript("OnClick")(widget)
        assert(widget.selectorRow and widget.list:IsShown() and widget.arrow.rikIcon=="chevron-up","Actual Settings selector did not open")
    end
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
    assert(c.group.selectorRow.spec.type=="dropdown" and c.group.arrow.rikIcon=="chevron-down","Studio did not reuse Settings dropdown")
    c.group:GetScript("OnClick")(c.group)
    local list=assert(c.group.list)
    assert(list:IsShown() and list.count>10 and list.dismiss:IsShown(),"Shared frame chooser has no discoverable groups")
    assert(c.group.arrow.rikIcon=="chevron-up","Shared disclosure did not open")
    local current=list.cursor
    RikUIStudio:GetScript("OnKeyDown")(RikUIStudio,"END")
    assert(list.cursor==list.count and list.buttons[current].mark:IsShown(),"Keyboard preview changed committed selection")
    RikUIStudio:GetScript("OnKeyDown")(RikUIStudio,"ESCAPE")
    assert(not list:IsShown() and not list.dismiss:IsShown() and c.group.arrow.rikIcon=="chevron-down","Escape did not restore shared chooser")
    c.group:GetScript("OnClick")(c.group)
    assert(c.group.list==list and list.cursor==current,"Reopening leaked a popup or committed cancelled choice")
    list.buttons[1]:GetScript("OnClick")(list.buttons[1])
    c.group:GetScript("OnClick")(c.group)
    assert(list.cursor==1 and list.buttons[1].mark:IsShown(),"Shared mouse selection was not retained")
    list.dismiss:GetScript("OnClick")(list.dismiss)
    assert(not list:IsShown(),"Outside dismissal did not close shared popup")
    local source=RikUI.SetupPack.Copy(RikUI.Profile)
    c.device:GetScript("OnClick")(c.device)
    RikUIStudio:GetScript("OnKeyDown")(RikUIStudio,"END")
    RikUIStudio:GetScript("OnKeyDown")(RikUIStudio,"ENTER")
    assert(RikUI.Studio.Device=="handheld" and RikUI.SetupPack.Equal(source,RikUI.Profile),"Shared keyboard selector applied a staged setup")
    c.device:GetScript("OnClick")(c.device)
    RikUIStudio:GetScript("OnKeyDown")(RikUIStudio,"HOME")
    RikUIStudio:GetScript("OnKeyDown")(RikUIStudio,"ENTER")
    assert(RikUI.Studio.Device=="desktop","Shared keyboard selector did not restore desktop")
    c.group:GetScript("OnClick")(c.group)
    assert(RikUI.Studio.ShowPage("share"))
    assert(not list:IsShown() and not list.dismiss:IsShown(),"Page exit left shared popup visible")
    assert(RikUI.Studio.ShowPage("layout"))
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
