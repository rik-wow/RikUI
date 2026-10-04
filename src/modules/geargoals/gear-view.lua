-- Shared RikUI chrome and controls; item icons and tooltips come from the client.
local core,g=RikUI,RikUI.GearGoals
local skin,media,shell=core.Skin,core.Media,core.Shell
local view={detailMode="compare",slot=16,page=1,kind=nil,search="",allLevels=false,mode="browse",source=1};g.View=view
local WIDTH,HEIGHT,PAGE=960,670,5
local muted={.67,.74,.81,1}
local function label(parent,value,role,width,height)
    local f=shell.Text(parent,value,role or "small");f:SetSize(width,height)
    f:SetJustifyV("TOP");f:SetWordWrap(true);return f
end
local function button(parent,value,width,action)
    local b=shell.Button(parent,value,action);b:SetWidth(width)
    b.label:SetJustifyH("CENTER");media.Font(b.label,"small");return b
end
local function enable(b,on)b:SetEnabled(on==true);b:SetAlpha(on and 1 or .4) end
local function accent(f,on)f:SetTextColor(unpack(on and skin.GOLD or skin.INK)) end
local function tooltip(frame,id)
    if not id or not GameTooltip then return end
    GameTooltip:SetOwner(frame,"ANCHOR_RIGHT");GameTooltip:SetHyperlink("item:"..id);GameTooltip:Show()
end
local function action(fn,...)
    local ok,reason=fn(...)
    view.message=ok and nil or reason
    view.Query();view.Refresh()
    return ok
end
local function sourceName(src)
    return src.kind=="dungeon" and ((src.dungeon or "Dungeon").." · "..(src.name or "Encounter"))
        or "Quest · "..(src.name or "Unknown quest")
end
local function goalFor(slot)
    for _,row in ipairs(g.Goals())do if row.slot==slot then return row end end
end
function view.SelectSlot(slot)
    if not g.SlotNames[slot] then return end
    view.slot,view.page,view.selected,view.source=slot,1,nil,1
    view.Query();view.Refresh()
end
function view.SelectItem(id,source)
    if view.selected~=id then view.detailMode=view.mode=="goals" and "source" or "compare" end
    view.selected,view.source=id,source or 1
    if view.Window then core.Scroll.SetOffset(view.Window.details,0) end
    view.Refresh()
end
function view.Query()
    if view.mode=="goals" then
        view.rows={}
        for _,row in ipairs(g.Goals())do
            local item=g.Item(row.itemID) or {name="Item #"..row.itemID.." · source unavailable",sources={}}
            view.rows[#view.rows+1]={id=row.itemID,item=item,level=item.level or 0,sources=g.Sources(row.itemID),goal=row}
        end
    else view.rows=g.Query(view.slot,{kind=view.kind,search=view.search,allLevels=view.allLevels,allSources=view.allLevels,maxLevel=(g.Level() or 60)+5}) end
end
function view.ChangePage(delta)
    view.selected=nil
    view.page=math.max(1,math.min(math.max(1,math.ceil(#(view.rows or {})/PAGE)),view.page+delta))
    view.Refresh()
end
local function build(parent,name,x,width)
    local f=CreateFrame("Frame",nil,parent);f:SetSize(width,486);f:SetPoint("TOPLEFT",x,-90)
    skin.Fill(f,skin.CONTROL,1);skin.Outline(f,skin.LINE)
    f.heading=label(f,name,"label",width-24,22);f.heading:SetPoint("TOPLEFT",12,-12)
    return f
end
local function slotPanel(w)
    local pane=build(w,"Equipment",16,174);w.slots={}
    for index,slot in ipairs(g.Slots)do
        local b=button(pane,"",74,function()view.mode="browse";view.SelectSlot(slot)end)
        b:SetSize(74,44);b:SetPoint("TOPLEFT",10+((index-1)%2)*80,-44-math.floor((index-1)/2)*48)
        b.icon=b:CreateTexture(nil,"ARTWORK");b.icon:SetSize(24,24);b.icon:SetPoint("TOP",0,-3);skin.CropIcon(b.icon,.06)
        b.label:ClearAllPoints();b.label:SetPoint("BOTTOMLEFT",2,2);b.label:SetPoint("BOTTOMRIGHT",-2,2)
        b.label:SetText(g.SlotNames[slot]);b.label:SetJustifyH("CENTER")
        b.selected=skin.Outline(b,skin.GOLD,0,nil,"OVERLAY")
        b:SetScript("OnEnter",function()
            if GameTooltip then GameTooltip:SetOwner(b,"ANCHOR_RIGHT");GameTooltip:SetInventoryItem("player",slot);GameTooltip:AddLine("Choose a gear goal for "..g.SlotNames[slot],unpack(skin.GOLD));GameTooltip:Show() end
        end)
        b:SetScript("OnLeave",function()if GameTooltip then GameTooltip:Hide()end end)
        w.slots[slot]=b
    end
end
local function itemPanel(w)
    local pane=build(w,"Candidates",202,300);w.candidateHeading=pane.heading;w.items={}
    w.filters={}
    for index,entry in ipairs({{label="All",kind=false},{label="Quests",kind="quest"},{label="Dungeons",kind="dungeon"}})do
        local b=button(pane,entry.label,88,function()
            view.kind,view.page,view.selected=entry.kind or nil,1,nil;view.Query();view.Refresh()
        end)
        b:SetPoint("TOPLEFT",12+(index-1)*92,-40);w.filters[index]=b
    end
    local search=CreateFrame("EditBox",nil,pane);w.search=search
    search:SetSize(276,28);search:SetPoint("TOPLEFT",12,-78);search:SetAutoFocus(false);search:SetMaxLetters(80)
    search:SetTextInsets(8,8,2,2);media.Font(search,"small");skin.Fill(search,skin.BACKING);skin.Outline(search,skin.LINE)
    search.hint=label(search,"Search item, quest or dungeon","small",260,18);search.hint:SetPoint("LEFT",8,0);search.hint:SetTextColor(unpack(muted))
    local pending=false
    search:SetScript("OnTextChanged",function()
        local value=search:GetText() or "";search.hint:SetShown(value=="")
        if value==view.search then return end
        view.search=value
        if pending then return end;pending=true
        local function refresh()pending=false;view.page,view.selected=1,nil;view.Query();view.Refresh()end
        if C_Timer and C_Timer.After then C_Timer.After(.15,refresh) else refresh()end
    end)
    search:SetScript("OnEscapePressed",function()search:ClearFocus()end)
    search:SetScript("OnEnterPressed",function()search:ClearFocus();view.SelectItem((view.rows[1] or {}).id)end)
    for index=1,PAGE do
        local b=button(pane,"",276,function(self)
            local row=self.row;if not row then return end
            if row.goal then view.slot=row.goal.slot end
            view.SelectItem(row.id,row.goal and row.goal.source or row.sources[1] and row.sources[1].index)
        end)
        b:SetSize(276,62);b:SetPoint("TOPLEFT",12,-120-(index-1)*66)
        b.label:Hide()
        b.icon=b:CreateTexture(nil,"ARTWORK");b.icon:SetSize(34,34);b.icon:SetPoint("TOPLEFT",8,-10);skin.CropIcon(b.icon,.06)
        b.title=label(b,"","label",218,34);b.title:SetPoint("TOPLEFT",50,-5)
        b.detail=label(b,"","small",218,22);b.detail:SetPoint("BOTTOMLEFT",50,4);b.detail:SetTextColor(unpack(muted))
        b.selected=skin.Outline(b,skin.GOLD,0,nil,"OVERLAY")
        b:SetScript("OnEnter",function()if b.row then tooltip(b,b.row.id)end end)
        b:SetScript("OnLeave",function()if GameTooltip then GameTooltip:Hide()end end)
        w.items[index]=b
    end
    w.previous=button(pane,"Previous",80,function()view.ChangePage(-1)end);w.previous:SetPoint("BOTTOMLEFT",12,10)
    w.next=button(pane,"Next",80,function()view.ChangePage(1)end);w.next:SetPoint("BOTTOMRIGHT",-12,10)
    w.count=label(pane,"","small",108,24);w.count:SetPoint("BOTTOM",0,12);w.count:SetJustifyH("CENTER")
end
local function detailPanel(w)
    local pane=build(w,"Compare & plan",514,430)
    pane.heading:SetWidth(154)
    w.compareTab=button(pane,"Compare",88,function()view.detailMode="compare";core.Scroll.SetOffset(w.details,0);view.Refresh()end)
    w.compareTab:SetPoint("TOPLEFT",180,-8)
    w.sourceTab=button(pane,"Source & steps",140,function()view.detailMode="source";core.Scroll.SetOffset(w.details,0);view.Refresh()end)
    w.sourceTab:SetPoint("LEFT",w.compareTab,"RIGHT",6,0)
    w.details=core.Scroll.Create(pane);w.details:SetPoint("TOPLEFT",12,-44);w.details:SetSize(406,368)
    w.blocks={}
    w.pin=button(pane,"Pin goal",120,function()
        if not view.selected then return end
        action(g.Pin,view.slot,view.selected,view.source);view.Query()
    end);w.pin:SetPoint("BOTTOMLEFT",12,12)
    w.pursue=button(pane,"Pursue goal",128,function()
        if view.detailMode=="compare" then view.detailMode="source";core.Scroll.SetOffset(w.details,0);view.Refresh();return end
        local row=goalFor(view.slot)
        if not row or row.itemID~=view.selected or row.source~=view.source then
            if not action(g.Pin,view.slot,view.selected,view.source) then return end
        end
        if not action(g.Pursue,view.slot) then return end
        view.message="Goal active. Quest guidance respects your existing skips, group and travel settings."
        view.Refresh()
    end);w.pursue:SetPoint("LEFT",w.pin,"RIGHT",8,0)
    w.remove=button(pane,"Remove",128,function()action(g.Remove,view.slot);view.Query();view.Refresh()end)
    w.remove:SetPoint("LEFT",w.pursue,"RIGHT",8,0)
    w.pursue.accent=skin.Outline(w.pursue,skin.GOLD,0,nil,"OVERLAY")
end
function view.Create()
    if view.Window then return view.Window end
    local w=CreateFrame("Frame","RikUIGearGoalsWindow",UIParent);view.Window=w
    w:SetSize(WIDTH,HEIGHT);w:SetPoint("CENTER");w:SetFrameStrata("DIALOG");w:SetClampedToScreen(true);w:SetMovable(true);w:EnableMouse(true);w:RegisterForDrag("LeftButton")
    w:SetScript("OnDragStart",function()w:StartMoving()end);w:SetScript("OnDragStop",function()w:StopMovingOrSizing()end)
    skin.WindowChrome(w,76,42)
    w.title=label(w,"Gear goals","heading",400,28);w.title:SetPoint("TOPLEFT",18,-14)
    w.subtitle=label(w,"Choose equipment · compare tradeoffs · plan a source","small",600,22);w.subtitle:SetPoint("TOPLEFT",18,-45);w.subtitle:SetTextColor(unpack(muted))
    w.close=button(w,"",30,function()w:Hide()end);w.close:SetPoint("TOPRIGHT",-14,-14)
    local cross=media.Icon(w.close,"close",14,"OVERLAY");cross:SetPoint("CENTER")
    w.browse=button(w,"Browse",96,function()view.mode="browse";view.detailMode="compare";view.page,view.selected=1,nil;view.Query();view.Refresh()end)
    w.browse:SetPoint("TOPRIGHT",-270,-32)
    w.goals=button(w,"My goals",108,function()view.mode="goals";view.detailMode="source";view.page,view.selected=1,nil;view.Query();view.Refresh()end)
    w.goals:SetPoint("LEFT",w.browse,"RIGHT",8,0)
    slotPanel(w);itemPanel(w);detailPanel(w)
    w.tracker=button(w,"",164,function()g.SetTracker(not g.Tracking())end)
    w.tracker:SetPoint("TOPLEFT",16,-590)
    w.stop=button(w,"Stop pursuit",120,function()g.Stop();view.Refresh()end)
    w.stop:SetPoint("LEFT",w.tracker,"RIGHT",8,0)
    w.level=button(w,"",164,function()view.allLevels=not view.allLevels;view.page,view.selected=1,nil;view.Query();view.Refresh()end)
    w.level:SetPoint("TOPRIGHT",-16,-590)
    w.sources=button(w,"Refresh sources",142,function()
        if g.Provider then g.Provider.Start(true);view.Query();view.Refresh()end
    end);w.sources:SetPoint("LEFT",w.stop,"RIGHT",8,0)
    w.status=label(w,"","small",700,30);w.status:SetPoint("BOTTOMLEFT",18,12)
    w:SetScript("OnShow",function()
        w:SetScale(math.min(1,math.max(.5,((UIParent:GetWidth() or WIDTH+32)-32)/WIDTH),math.max(.5,((UIParent:GetHeight() or HEIGHT+32)-32)/HEIGHT)))
        view.Query();view.Refresh()
        if view.Badges then for _,b in pairs(view.Badges)do b:Show()end end
    end)
    w:SetScript("OnHide",function()
        w.search:ClearFocus()
        if view.Badges then for _,b in pairs(view.Badges)do b:Hide()end end
    end)
    w:EnableKeyboard(true)
    w:SetScript("OnKeyDown",function(_,key)
        w:SetPropagateKeyboardInput(false)
        if w.search:HasFocus() then w:SetPropagateKeyboardInput(true);return end
        if key=="ESCAPE" then w:Hide()
        elseif key=="LEFT" or key=="RIGHT" then view.ChangePage(key=="LEFT" and -1 or 1)
        elseif key=="UP" or key=="DOWN" then
            local index=0;for i,row in ipairs(view.rows or {})do if row.id==view.selected then index=i;break end end
            index=math.max(1,math.min(#(view.rows or {}),index+(key=="UP" and -1 or 1)))
            local row=(view.rows or {})[index]
            if row then view.page=math.ceil(index/PAGE);if row.goal then view.slot=row.goal.slot end;view.SelectItem(row.id,row.goal and row.goal.source or row.sources[1] and row.sources[1].index)end
        elseif key=="TAB" then w.search:SetFocus()
        else w:SetPropagateKeyboardInput(true)end
    end)
    UISpecialFrames=UISpecialFrames or {};table.insert(UISpecialFrames,"RikUIGearGoalsWindow")
    w:Hide();return w
end
-- Reused scroll blocks: no unbounded row creation on repeated browsing.
local function block(w,index,value,height,click,icon)
    local b=w.blocks[index]
    if not b then
        b=button(w.details.content,"",388,function(self)if self.click then self.click()end end)
        b.label:SetJustifyH("LEFT");b.label:SetWordWrap(true);b.label:SetJustifyV("MIDDLE")
        b.icon=b:CreateTexture(nil,"ARTWORK");b.icon:SetSize(30,30);b.icon:SetPoint("LEFT",8,0);skin.CropIcon(b.icon,.06)
        w.blocks[index]=b
    end
    if b.columns then for _,f in ipairs(b.columns)do f:Hide()end;b.changeIcon:Hide();b.rule:Hide()end
    if b.statBars then for _,bar in ipairs(b.statBars)do bar.track:Hide();bar.fill:Hide()end end
    b.label:Show()
    b:SetSize(388,height);b.label:SetText(value);b.click=click
    b.surface.fill:SetAlpha(click and 1 or 0)
    for _,edge in ipairs(b.surface.edge or {})do edge:SetShown(click~=nil)end
    b.surface.light:SetShown(click~=nil);b.surface.shade:SetShown(click~=nil)
    b:EnableMouse(click~=nil)
    -- Only actionable rows have button furniture.
    b.icon:SetShown(icon~=nil);if icon then b.icon:SetTexture(icon)end
    b.label:ClearAllPoints();b.label:SetPoint("TOPLEFT",icon and 46 or 8,-4);b.label:SetPoint("BOTTOMRIGHT",-8,4)
    accent(b.label,false);b:Show();return b
end
local function requirements(q)
    local result={}
    if (q.requiredLevel or 0)>0 then result[#result+1]="Quest requires level "..q.requiredLevel end
    if (q.requiredMaxLevel or 0)>0 then result[#result+1]="Maximum quest level "..q.requiredMaxLevel end
    local labels={requiredSkill="Profession or skill requirement",requiredMinRep="Minimum reputation",
        requiredMaxRep="Maximum reputation",requiredRanks="Rank requirement",requiredSpell="Required ability",
        requiredSpecialization="Specialization",availableStartingWith="Available after quest",
        availableUntilCompleted="Unavailable after quest",disabledByQuest="Excluded by quest"}
    for _,field in ipairs({"requiredSkill","requiredMinRep","requiredMaxRep","requiredRanks"})do
        local v=q[field]
        if type(v)=="table" and next(v) then
            local values={};for _,n in ipairs(v)do if type(n)=="number" or type(n)=="string" then values[#values+1]=tostring(n) end end
            result[#result+1]=labels[field]..": "..table.concat(values,", ").." (reference identifiers; verify in game)"
        end
    end
    for _,field in ipairs({"requiredSpell","requiredSpecialization","availableStartingWith","availableUntilCompleted","disabledByQuest"})do
        if (q[field] or 0)>0 then result[#result+1]=labels[field].." #"..q[field].." (verify in game)" end
    end
    if q.exclusiveTo and #q.exclusiveTo>0 then result[#result+1]="Exclusive quest branch; completion can exclude alternatives" end
    return table.concat(result,"\n")
end
-- Reusable equipment cards and aligned numeric columns; tooltips use full live links.
local function equipped(slot)
    local ok,link=core.Secret.Read(GetInventoryItemLink,"player",slot)
    if not ok or core.Secret.IsSecret(link) then return {name="Equipment unavailable",slot=slot}end
    if link==nil then return {name="Empty slot",slot=slot}end
    if type(link)~="string" then return {name="Equipment unavailable",slot=slot}end
    local fn=C_Item and C_Item.GetItemInfo or GetItemInfo
    local known,name,_,quality,_,_,_,_,_,_,icon=core.Secret.Read(fn,link)
    return {slot=slot,link=link,name=known and not core.Secret.IsSecret(name) and type(name)=="string" and name or "Loading equipped item",
        icon=known and not core.Secret.IsSecret(icon) and icon or nil,
        quality=known and not core.Secret.IsSecret(quality) and quality or nil}
end
local function comparisonHeader(w,item,meta,comparison)
    local host=w.comparison
    if not host then
        host=CreateFrame("Frame",nil,w.details.content);w.comparison=host
        host:SetWidth(388);host.cards={}
        host.current=label(host,"Equipped","small",186,20);host.current:SetPoint("TOPLEFT",0,0);host.current:SetTextColor(unpack(muted))
        host.candidate=label(host,"Candidate","small",186,20);host.candidate:SetPoint("TOPLEFT",202,0);accent(host.candidate,true)
        host.arrow=media.Icon(host,"chevron-right",16,"OVERLAY");host.arrow:SetPoint("TOPLEFT",186,-58)
        for i=1,3 do
            local card=button(host,"",186,nil);card.label:Hide();host.cards[i]=card
            card.icon=card:CreateTexture(nil,"ARTWORK");card.icon:SetSize(38,38);card.icon:SetPoint("TOPLEFT",8,-10);skin.CropIcon(card.icon,.06)
            card.name=label(card,"","label",124,54);card.name:SetPoint("TOPLEFT",54,-8)
            card.slot=label(card,"","small",124,20);card.slot:SetPoint("TOPLEFT",54,-65);card.slot:SetTextColor(unpack(muted))
            card:SetScript("OnEnter",function()
                if card.link and GameTooltip then GameTooltip:SetOwner(card,"ANCHOR_RIGHT");GameTooltip:SetHyperlink(card.link);GameTooltip:Show()end
            end)
            card:SetScript("OnLeave",function()if GameTooltip then GameTooltip:Hide()end end)
        end
        host.note=label(host,"","small",388,28)
    end
    for _,card in ipairs(host.cards)do card:Hide()end
    local replacing=item.inventoryType==17 and {16,17} or {view.slot}
    local function fill(card,data)
        card.link=data.link;card.name:SetText(data.name)
        card.icon:SetTexture(data.icon or "Interface/Icons/INV_Misc_QuestionMark")
        card.slot:SetText(data.slot and g.SlotNames[data.slot] or meta and ((meta.subtype or "").." · level "..(meta.minLevel or "?")) or "Reference item")
        card.name:SetTextColor(unpack(skin.INK))
        local h=math.max(26,(card.name:GetStringHeight() or 0)+2)
        card.name:SetHeight(h);card.slot:ClearAllPoints();card.slot:SetPoint("TOPLEFT",54,-h-12)
        local sh=math.max(16,(card.slot:GetStringHeight() or 0)+2);card.slot:SetHeight(sh)
        card:SetHeight(math.max(66,h+sh+22));card:Show();return card:GetHeight()
    end
    local height=20
    for i,slot in ipairs(replacing)do
        local card=host.cards[i];card:ClearAllPoints();card:SetPoint("TOPLEFT",0,-height)
        height=height+fill(card,equipped(slot))+6
    end
    local candidate=host.cards[3];candidate:ClearAllPoints();candidate:SetPoint("TOPLEFT",202,-20)
    height=math.max(height,20+fill(candidate,{name=meta and meta.name or item.name,icon=meta and meta.icon or item.icon,link=meta and meta.link})+6)
    host.note:ClearAllPoints();host.note:SetPoint("TOPLEFT",0,-height)
    host.note:SetText(item.inventoryType==17 and "Two-handed: totals replace both equipped hands."
        or comparison.handConflict and "Your two-handed main hand must also be replaced."
        or "Hover either item to inspect its full tooltip.")
    host.note:SetTextColor(unpack(comparison.handConflict and {1,.7,.55,1} or muted))
    local noteHeight=math.max(22,(host.note:GetStringHeight() or 0)+4);host.note:SetHeight(noteHeight)
    host:SetHeight(height+noteHeight+8);host:ClearAllPoints();host:SetPoint("TOPLEFT",0,0);host:Show()
    return host:GetHeight()
end
local function statColumns(b,values,delta)
    if not b.columns then
        b.columns={}
        local x,width={8,156,220,292},{142,58,58,88}
        for i=1,4 do
            local f=label(b,"","small",width[i],26);f:SetPoint("TOPLEFT",x[i],-4)
            if i>1 then f:SetJustifyH("RIGHT")end
            b.columns[i]=f
        end
        b.changeIcon=media.Icon(b,"minus",12,"OVERLAY");b.changeIcon:SetPoint("LEFT",290,0)
        b.rule=skin.Fill(b,{.18,.22,.27,.3});b.rule:ClearAllPoints();b.rule:SetPoint("BOTTOMLEFT",8,0);b.rule:SetPoint("BOTTOMRIGHT",-8,0);b.rule:SetHeight(1)
        b.statBars={}
        for i=1,2 do
            local track=b:CreateTexture(nil,"BACKGROUND");track:SetColorTexture(.18,.22,.27,.5);track:SetSize(52,3)
            track:SetPoint("BOTTOMRIGHT",b,"BOTTOMLEFT",i==1 and 214 or 278,3)
            local fill=b:CreateTexture(nil,"ARTWORK");fill:SetColorTexture(unpack(i==1 and muted or skin.GOLD));fill:SetHeight(3)
            fill:SetPoint("LEFT",track,"LEFT",0,0);b.statBars[i]={track=track,fill=fill}
        end
    end
    b.label:Hide()
    local height=26
    for i,f in ipairs(b.columns)do
        f:SetText(values[i]);f:Show()
        f:SetTextColor(unpack(delta==nil and muted or skin.INK))
        local h=math.max(18,(f:GetStringHeight() or 0)+4);f:SetHeight(h);height=math.max(height,h+8)
    end
    local before,after=tonumber(values[2]),tonumber(values[3])
    local maximum=before and after and math.max(before,after) or 0
    local bars=delta~=nil and before and after and before>=0 and after>=0 and maximum>0
    for i,bar in ipairs(b.statBars)do
        bar.track:SetShown(bars==true);bar.fill:SetShown(bars==true and (i==1 and before or after)>0)
        if bars then bar.fill:SetWidth(math.max(.1,52*(i==1 and before or after)/maximum))end
    end
    if bars then height=height+6 end
    b.rule:Show();b.changeIcon:SetShown(delta~=nil and delta~=0)
    if delta~=nil then
        local color=delta>0 and {.55,.9,.8,1} or delta<0 and {1,.7,.55,1} or muted
        b.columns[4]:SetTextColor(unpack(color))
        media.SetIcon(b.changeIcon,delta>0 and "chevron-up" or delta<0 and "chevron-down" or "minus")
        b.changeIcon:SetVertexColor(unpack(color))
    end
    b:SetHeight(height);return height
end
function view.RefreshDetails()
    local w=view.Window;if not w then return end
    local index,y=0,0
    local function add(value,height,click,icon)
        index=index+1;if index>128 then return end
        local b=block(w,index,value,height,click,icon);b:ClearAllPoints();b:SetPoint("TOPLEFT",0,-y)
        height=math.max(height,(b.label:GetStringHeight() or 0)+12);b:SetHeight(height);y=y+height+4
        return b
    end
    local id=view.selected;local item=id and g.Item(id);local meta=id and g.Meta(id,true)
    local row=goalFor(view.slot)
    if w.comparison then w.comparison:Hide()end
    if not item then
        if row and row.itemID==id then
            add("Saved goal · item #"..row.itemID,48)
            add("Its source is currently unavailable. This goal is preserved; refresh sources or remove it below.",72)
        elseif not core.GearCatalog then
            add("Source browsing needs QuestieDB with Forever data.",54)
            add("Install and enable the optional QuestieDB addon, then reload. Your saved goals remain on this character.",72)
            add("Check source availability",38,function()if g.Provider then g.Provider.Start(true);view.Query();view.Refresh()end end)
        elseif g.Provider and g.Provider.Progress() then add("Preparing equipment sources. This is a one-time background index for this session.",72)
        elseif view.mode=="goals" then add("No goals match this view. Browse equipment, compare a source, then pin it for this character.",72)
        else
            add("No candidates for "..(g.SlotNames[view.slot] or "this slot").." with these filters.",54)
            add("Try another slot, clear the search or select All levels & sources. Not every item has a supported source.",72)
        end
    elseif view.detailMode=="compare" then
        local comparison=g.Compare(id,view.slot)
        y=comparisonHeader(w,item,meta,comparison)
        if comparison.status=="known" then
            local b=add("",30);local initial=b:GetHeight()
            y=y+statColumns(b,{"Stat","Current","New","Change"},nil)-initial
            if #comparison.deltas==0 then add("No numeric changes reported. Check the tooltip for weapon damage and effects.",48)end
            for _,delta in ipairs(comparison.deltas)do
                local change=delta.delta==0 and "same" or string.format("%+.1f",delta.delta):gsub("%.0$","")
                b=add("",30);initial=b:GetHeight()
                y=y+statColumns(b,{delta.label,tostring(delta.before),tostring(delta.after),change},delta.delta)-initial
            end
            add("Tradeoffs only · inspect effects in the item tooltips.",30)
        else
            add(comparison.detail,42)
            add("Retry item data",34,function()g.Retry();view.Refresh()end)
            add("Unavailable values stay unknown; no estimated upgrade.",38)
        end
    else
        add(meta and meta.name or item.name,48,nil,meta and meta.icon or item.icon)
        if row and row.itemID==id then add(row.seen and "Acquired · observed in your inventory" or "Pinned for this character",34)end
        add("Where to get it · reference sources",30)
        for _,src in ipairs(g.Sources(id))do
            local b=add((src.index==view.source and "Selected · " or "")..sourceName(src)
                ..(src.completed and " · quest already completed" or src.group and " · group quest" or ""),48,
                function()view.source=src.index;core.Scroll.SetOffset(w.details,0);view.Refresh()end,
                media.IconPath(src.kind=="dungeon" and "groupfinder" or "quest"))
            if b then accent(b.label,src.index==view.source)end
        end
        local src=item.sources[view.source]
        if src and src.kind=="quest" then
            if core.QuestPlanner and core.QuestPlanner.enabled then add("Open quest guide",30,function()view.Window:Hide();core.QuestPlanner.View.Open()end)end
            local path=g.Path(src.id,row and row.itemID==id and row.branch)
            if path.issue then add(path.issue,48)end
            if #path.choices>0 then
                add("Choose one prerequisite branch. No alternative is silently selected.",48)
                for _,choice in ipairs(path.choices)do
                    add(choice.name.." · use this branch",42,function()
                        if not row or row.itemID~=id then if not action(g.Pin,view.slot,id,view.source)then return end end
                        action(g.ChooseBranch,view.slot,choice.id)
                    end)
                end
            end
            add("Prerequisites & progress",30)
            for _,quest in ipairs(path.rows)do
                add(quest.name.." · "..quest.state..(quest.level and " · level "..quest.level or ""),42,
                    function()
                        if core.QuestPlanner and core.QuestPlanner.enabled and core.QuestPlanner.View then
                            local ok,reason=core.QuestPlanner.Controller.Select(quest.id)
                            if not ok then view.message=reason end
                            if ok then view.Window:Hide();core.QuestPlanner.View.Open() else view.Refresh() end
                        else view.message="Enable Quest planner in RikUI settings, then reload.";view.Refresh()end
                    end)
                local detail=requirements(quest.row)
                if detail~="" then add(detail,math.min(140,26*(select(2,detail:gsub("\n",""))+1)))end
            end
            local p=core.QuestPlanner;local ctx=p and p.Controller and p.Controller.Context()
            local offer=ctx and ctx.rewards and ctx.rewards[src.id]
            if offer and offer.authority=="observed-offer" then
                local found
                for _,v in ipairs(offer.items or {})do if v.itemID==id then found="Confirmed in the current quest's fixed reward offer" end end
                for _,v in ipairs(offer.choices or {})do if v.itemID==id then found="Confirmed as a choice in the current quest reward offer" end end
                add(found or "Current observed offer does not list this item; verify the source before pursuing.",54)
            end
        elseif src then add("Dungeon source requires a group. This is a maintained reference: difficulty, lockout, drop rate and current payout are unverified.",72)end
        if row and row.itemID==id and row.sourceMissing then add("Your pinned source is no longer available. Select and pin a current source before pursuing it again.",64)end
        add("Verify the reward in game. RikUI never equips items or selects quest rewards.",48)
    end
    for i=index+1,#w.blocks do w.blocks[i]:Hide()end
    core.Scroll.SetContentHeight(w.details,math.max(368,y))
    local src=item and item.sources[view.source]
    local valid=item~=nil and src~=nil
    enable(w.pin,valid);enable(w.pursue,item~=nil and (view.detailMode=="compare" or valid and not (row and row.itemID==id and row.seen)))
    accent(w.compareTab.label,view.detailMode=="compare");accent(w.sourceTab.label,view.detailMode=="source")
    enable(w.remove,row~=nil and row.itemID==id)
    w.pin.label:SetText(row and row.itemID==id and row.source==view.source and "Pinned goal" or "Pin goal")
    w.pursue.label:SetText(view.detailMode=="compare" and "Choose source" or src and src.kind=="dungeon" and "Track source" or "Pursue goal")
end
function view.Refresh()
    local w=view.Window
    if g.RefreshTracker then g.RefreshTracker()end
    if not w or not w:IsShown() then return end
    local rows=view.rows or {};view.page=math.min(view.page,math.max(1,math.ceil(#rows/PAGE)))
    if not view.selected then
        local first=rows[(view.page-1)*PAGE+1]
        if first then view.selected=first.id;view.source=first.goal and first.goal.source or first.sources[1] and first.sources[1].index or 1;if first.goal then view.slot=first.goal.slot end end
    end
    for slot,b in pairs(w.slots)do
        local ok,icon=core.Secret.Read(GetInventoryItemTexture,"player",slot)
        b.icon:SetTexture(ok and not core.Secret.IsSecret(icon) and icon or "Interface/Icons/INV_Misc_QuestionMark")
        for _,edge in ipairs(b.selected)do edge:SetShown(slot==view.slot)end
        accent(b.label,slot==view.slot)
    end
    for i,b in ipairs(w.items)do
        local row=rows[(view.page-1)*PAGE+i];b.row=row;b:SetShown(row~=nil)
        if row then
            local meta=g.Meta(row.id,true);b.title:SetText(meta and meta.name or row.item.name)
            b.icon:SetTexture(meta and meta.icon or row.item.icon or "Interface/Icons/INV_Misc_QuestionMark")
            local first=row.sources[1]
            b.detail:SetText(row.goal and ((g.SlotNames[row.goal.slot] or "").." · "..(row.goal.seen and "Acquired" or "Pinned"))
                or "Lv "..row.level.." · "..(first and first.kind=="dungeon" and first.dungeon or "Quest reward"))
            accent(b.title,row.id==view.selected)
            for _,edge in ipairs(b.selected)do edge:SetShown(row.id==view.selected)end
        end
    end
    enable(w.previous,view.page>1);enable(w.next,view.page*PAGE<#rows)
    w.count:SetText(view.page.." / "..math.max(1,math.ceil(#rows/PAGE)))
    w.candidateHeading:SetText((view.mode=="goals" and "Goals" or "Candidates").." ("..#rows..")")
    accent(w.browse.label,view.mode=="browse");accent(w.goals.label,view.mode=="goals")
    for i,b in ipairs(w.filters)do accent(b.label,(i==1 and view.kind==nil) or (i==2 and view.kind=="quest") or (i==3 and view.kind=="dungeon"));enable(b,view.mode=="browse")end
    w.search:SetEnabled(view.mode=="browse")
    w.level.label:SetText(view.allLevels and "All levels & sources" or "Up to level "..((g.Level() or 60)+5))
    local status=view.message or (not g.CurrentCatalog() and "Catalog build differs; sources and requirements need live verification."
        or view.mode=="goals" and "Up to 8 goals per character. Acquired goals remain until you remove them." or "Up/Down: select · Left/Right: pages · Tab: search · hover items for tooltips")
    if g.Provider then
        local progress=g.Provider.Progress()
        if progress then status="Indexing source references: "..math.floor(progress*100).."% · preparing sources"
        elseif not core.GearCatalog or g.Provider.failed then status=g.Provider.status end
    end
    local issue=core.Store and core.Store.BackupIssue and core.Store.BackupIssue()
    if issue then status=status.." · Backup: "..issue end
    w.status:SetText(status)
    w.tracker.label:SetText(g.Tracking() and "Tracker: on" or "Tracker: off")
    enable(w.stop,g.Focused()~=nil)
    view.RefreshDetails()
end
function view.Show(slot)
    if core.Profile and core.Profile.modules.geargoals==false then core:Print("Enable Gear goals and reload.");return end
    if g.Provider then g.Provider.Start() end
    view.Create()
    if slot then view.SelectSlot(slot)end
    view.Window:Show();view.Window:Raise();view.Refresh()
end
