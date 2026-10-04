return function(check)
    local env=require("wow_stub");local widget=require("widget_stub");local undo=widget.install()
    local original={C_Item=C_Item,GetBuildInfo=GetBuildInfo,GetInventoryItemLink=GetInventoryItemLink}
    widget.loadAddon(env,{"src/ui/skin.lua","src/ui/scroll.lua","src/ui/shell.lua","src/modules/geargoals/gear-model.lua",
        "src/modules/geargoals/gear-view.lua","src/modules/geargoals/geargoals.lua"},{reducedMotion=true},false,function()
        C_Item={GetItemCount=function()return 0 end,GetItemInfo=function(id)return "Reward","item:"..id,2,15,10,"Weapon","Sword",1,"INVTYPE_WEAPON",135274 end,
            GetItemStats=function(link)return {ITEM_MOD_STAMINA_SHORT=link=="item:100" and 5 or 2}end}
        GetBuildInfo=function()return "1.60.1","70205"end
        GetInventoryItemLink=function()return "item:50"end
    end)
    local g=RikUI.GearGoals
    local nativeButton=RikUI.Shell.Button
    RikUI.Shell.Button=function(parent,text,callback)
        assert(callback==nil or type(callback)=="function","Shared button callback must be a function")
        return nativeButton(parent,text,callback)
    end
    RikUI.GearCatalog={identity={build="1.60.1.70205"},items={[100]={name="Reward",inventoryType=13,itemLevel=15,level=10,
        icon=135274,sources={{kind="quest",id=1,name="Quest"}}}},slots={[16]={100}},quests={[1]={name="Quest",requiredLevel=10}},variants={}}
    g.View.Show(16)
    local w=g.View.Window
    check("Gear view opens actual shared window",w:IsShown() and w.slots[16]~=nil)
    check("Gear view selects indexed candidate",g.View.selected==100 and w.items[1].row.id==100)
    check("Gear comparison shows full equipped and candidate links",w.comparison.cards[1].link=="item:50" and w.comparison.cards[3].link=="item:100")
    check("Gear comparison uses short readable table headers",w.blocks[1].columns[2]:GetText()=="Current" and w.blocks[1].columns[3]:GetText()=="New")
    check("Gear pagination is one line with a separate candidate count",w.count:GetText()=="1 / 1" and w.candidateHeading:GetText()=="Candidates (1)")
    check("Gear stat bars share a scale within each tradeoff",w.blocks[2].statBars[1].fill:GetWidth()==52*2/5 and w.blocks[2].statBars[2].fill:GetWidth()==52)
    check("Gear stat comparison has aligned signed columns",w.blocks[2].columns[2]:GetText()=="2" and w.blocks[2].columns[3]:GetText()=="5" and w.blocks[2].columns[4]:GetText()=="+3")
    RikUI.GearCatalog.items[100].inventoryType=17;g.View.Refresh()
    check("Gear two-hand comparison visibly includes both hands",w.comparison.cards[1]:IsShown() and w.comparison.cards[2]:IsShown() and w.comparison.cards[2].slot:GetText()=="Off hand")
    check("Gear two-hand stat totals include both replaced links",w.blocks[2].columns[2]:GetText()=="4" and w.blocks[2].columns[4]:GetText()=="+1")
    RikUI.GearCatalog.items[100].inventoryType=13;g.View.Refresh()
    check("Gear normal comparison removes stale off-hand card",not w.comparison.cards[2]:IsShown())
    env.runScript(w.pin,"OnClick")
    check("Gear GUI pin writes character settings",#g.Goals()==1 and g.Goals()[1].itemID==100)
    env.runScript(w.pursue,"OnClick")
    check("Gear comparison primary action opens source before pursuit",g.View.detailMode=="source" and g.Focused()==nil and not w.comparison:IsShown())
    check("Gear source view clears recycled stat bars",not w.blocks[2].statBars[1].track:IsShown())
    env.runScript(w.compareTab,"OnClick")
    check("Gear comparison tab restores equipment and stat view",g.View.detailMode=="compare" and w.comparison:IsShown())
    local n=#w.blocks
    for i=1,10 do g.View.Refresh()end
    check("Gear detail furniture bounded across refreshes",#w.blocks==n)
    local character,mainHand=CharacterFrame,CharacterMainHandSlot
    CharacterFrame=CreateFrame("Frame",nil,UIParent)
    CharacterMainHandSlot=CreateFrame("Button",nil,CharacterFrame)
    local equipAction=function()end;CharacterMainHandSlot:SetScript("OnClick",equipAction)
    g.AttachCharacter()
    env.runScript(g.View.CharacterEntry,"OnClick")
    check("Gear character entry opens the shared browser",w:IsShown())
    env.runScript(g.View.Badges[16],"OnClick")
    check("Gear character slot entry chooses its equipment slot",g.View.slot==16)
    check("Gear slot entry preserves native equipment action",CharacterMainHandSlot:GetScript("OnClick")==equipAction)
    CharacterFrame,CharacterMainHandSlot=character,mainHand
    env.runScript(w,"OnKeyDown","TAB")
    check("Gear keyboard can reach search",w.search.keyboard~=false)
    env.runScript(w,"OnKeyDown","ESCAPE")
    -- The stub doesn't track EditBox focus, so EscapePressed is exercised separately.
    env.runScript(w.search,"OnEscapePressed")
    check("Gear footer controls stay above status",w.tracker.point[3]==-590 and w:GetHeight()==670)
    g.SetTracker(true);g.Pursue(16);g.RefreshTracker()
    check("Gear optional tracker registered as real movable group",g.Tracker and RikUI.Layout.Groups.geargoals)
    RikUI.GearCatalog=nil
    env.runScript(w.goals,"OnClick");w:Show()
    check("Gear unavailable provider keeps saved goal selectable",g.View.selected==100 and w.remove:IsEnabled())
    env.runScript(w.remove,"OnClick");g.RefreshTracker()
    check("Gear GUI can remove a goal without its provider",#g.Goals()==0)
    check("Gear removing goal hides tracker",not g.Tracker:IsShown())
    undo()
    for key,value in pairs(original)do _G[key]=value end
end
