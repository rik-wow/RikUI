-- Exercise the real game Export live operation and its copy dialog.
function RikRenderStudioLiveExport()
    RikRenderScreenState()
    assert(RikUI.Studio.Open())
    local code,reason=RikUI.Studio.Export()
    assert(code,reason)
    assert(RikUI.SetupPack.Decode(code))
    local clicked=false
    for _,child in ipairs({RikUIStudio:GetChildren()}) do
        if child.label and child.label.GetText and child.label:GetText()=="Export live" then
            child:GetScript("OnClick")(child);clicked=true;break
        end
    end
    assert(clicked,"Export live control missing")
    local window=assert(RikUI.Sharing.Window)
    assert(window.edit:GetText()==code,"Export dialog truncated the code")
    assert(window:GetFrameStrata()=="FULLSCREEN_DIALOG","Export window shares Studio layer")
    assert(not RikUIStudio:IsShown(),"Studio remains behind translucent export dialog")
    RikUI.Sharing.Close()
    assert(RikUIStudio:IsShown(),"Closing export did not restore Studio")
    assert(not window:IsShown(),"Closing export left its dialog visible")
    for _,child in ipairs({RikUIStudio:GetChildren()}) do
        if child.label and child.label.GetText and child.label:GetText()=="Export live" then
            child:GetScript("OnClick")(child);break
        end
    end
    assert(window:IsShown() and not RikUIStudio:IsShown(),"Reopened export failed to isolate its dialog")
    assert(window.edit:GetText()==code,"Reopened export altered its code")
    local record=UIParent:CreateFontString("RikRenderLiveExportCode","OVERLAY","GameFontNormal")
    record:SetText("STUDIO_LIVE_EXPORT "..code);record:Hide()
end
