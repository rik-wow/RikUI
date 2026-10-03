-- The addon journey: choose, select parts, fit/review, try on, apply, personalize, share/update.
local core,studio,pack=RikUI,RikUI.Studio,RikUI.SetupPack
local controls=core.WizardControls
local window,accepts,history,redo=nil,{}, {},{}
local privacy={chat=true,planner=true,inventory=true,sharing=true}
local attribution=true
local returnFromSharing=false
local previewMode=false
local currentPage="choose"
local pages,refreshers,nav,buttons={},{},{},{}
studio.Controls=buttons
local function report(ok,reason)
    local detail=type(reason)=="table" and ((reason.status or "Result")..": "..tostring(reason.error or reason.reason or "settings written; review reload requirements")) or reason
    if window then window.status:SetText(ok and (type(detail)=="string" and detail or "Done. Review reload requirements below.") or tostring(detail)) end
    if window then studio.RefreshWindow() end
end
local function sharingDialog(...)
    local ok=core.Sharing.OpenDialog(...)
    if ok and core.Sharing.Window then
        local dialog=core.Sharing.Window
        dialog:SetFrameStrata("FULLSCREEN_DIALOG")
        if not dialog.rikStudioReturnHook then
            dialog.rikStudioReturnHook=true
            dialog:HookScript("OnHide",function()
                if returnFromSharing then
                    returnFromSharing=false
                    if window and not InCombatLockdown() then studio.RefreshWindow();window:Show() end
                end
            end)
        end
        returnFromSharing=window and window:IsShown() or false
        if returnFromSharing then window:Hide() end
    end
    return ok
end
local function snapshot() return {draft=pack.Copy(studio.Draft),selected=pack.Copy(studio.Selected),device=studio.Device,activity=studio.Activity} end
local function remember()
    if studio.Draft then history[#history+1]=snapshot();if #history>20 then table.remove(history,1) end end
    redo={}
end
function studio.Select(name)
    studio.State()
    remember();local value,reason=pack.Bundled(name);if not value then return nil,reason end
    studio.Draft=value;studio.Selected=pack.Copy(value.components);studio.Selected.character=false;accepts={}
    return true
end
function studio.Recipe(name)
    studio.Selected={}
    if name=="everything" then for c in pairs(pack.Components) do studio.Selected[c]=c~="character" end
    elseif pack.Components[name] then studio.Selected[name]=true else return nil,"Unknown component recipe" end
    return true
end
function studio.Remix()
    if not studio.Draft then return end
    if studio.Draft.creator=="You" then
        local installed=studio.State().installed and pack.Decode(studio.State().installed)
        if installed and installed.id==studio.Draft.id then studio.Draft.revision=math.max(studio.Draft.revision,installed.revision+1) end
        return
    end
    local p=studio.Draft
    p.ancestry={id=p.id,revision=p.revision,creator=p.creator}
    p.id="remix-"..core.Codec.ChecksumHex(assert(pack.Encode(p)));p.revision=1;p.creator="You"
    p.title=(p.title:sub(1,72).." remix")
end
function studio.EditTheme(key,value)
    if not studio.Draft then return nil,"Choose a pack" end
    remember();studio.Remix();studio.Draft.profile.theme=studio.Draft.profile.theme or pack.Copy(pack.Themes.classic.theme)
    if key=="font" or key=="scale" or key=="textScale" then studio.Draft.adjustments=studio.Draft.adjustments or {};studio.Draft.adjustments[key]=value else studio.Draft.adjustments=studio.Draft.adjustments or {};studio.Draft.adjustments.theme=studio.Draft.adjustments.theme or pack.Copy(studio.Draft.profile.theme);studio.Draft.adjustments.theme[key]=value end
    return pack.Validate(studio.Draft)
end
function studio.ThemeExport()
    if not studio.Draft then return nil,"Choose a pack" end
    local resolved,reason=studio.Resolve();if not resolved then return nil,reason end
    local p=resolved.profile
    local value=pack.FromProfile({theme=pack.Copy(p.theme),font=p.font,borderColor=pack.Copy(p.borderColor),textScale=p.textScale},
        {id=studio.Draft.id:sub(1,58).."-theme",title=studio.Draft.title:sub(1,74).." theme",creator=studio.Draft.creator},{})
    if not value then return nil,"Theme exceeds metadata capacity" end
    value.components={appearance=true}
    return pack.Encode(value)
end
function studio.DraftUndo(forward)
    local from,to=forward and redo or history,forward and history or redo
    if #from==0 then return nil,"No edit to undo" end
    to[#to+1]=snapshot();local saved=table.remove(from)
    studio.Draft,studio.Selected,studio.Device,studio.Activity=saved.draft,saved.selected,saved.device,saved.activity;return true
end
local groupIndex,conflictIndex=1,1
local function groupKeys()
    local keys={};for key in pairs(studio.Draft and studio.Draft.groups or {}) do keys[#keys+1]=key end;table.sort(keys);return keys
end
function studio.MoveGroup(dx,dy)
    local keys=groupKeys();local key=keys[groupIndex];if not key then return nil,"No movable group in this pack" end
    local resolved,reason=studio.Resolve();if not resolved then return nil,reason end
    local position=resolved.profile.positions[key];if not position then return nil,"No resolved anchor for this group" end
    remember();studio.Remix();studio.Draft.adjustments=studio.Draft.adjustments or {};studio.Draft.adjustments.positions=studio.Draft.adjustments.positions or {}
    position=pack.Copy(position);position.x=math.floor((position.x+dx)/8+0.5)*8;position.y=math.floor((position.y+dy)/8+0.5)*8
    studio.Draft.adjustments.positions[key]=position
    return pack.Validate(studio.Draft)
end

local names={appearance="Appearance & chat",hud="Combat HUD",nameplates="Nameplates",group="Party & raid",navigation="Map & quests",inventory="Bags & loot",character="Character setup"}
local groupNames={main="Main action bar",bar2="Action bar 2",bar3="Action bar 3",bar4="Action bar 4",bar5="Action bar 5",chat="Chat",bags="Bags",castplayer="Player cast bar",casttarget="Target cast bar",castfocus="Focus cast bar",castpet="Pet cast bar",player="Player",target="Target",tot="Target of target",petframe="Pet",stance="Stance bar",minimap="Minimap",questtracker="Quest tracker"}
local steps={{"choose","1  Choose"},{"parts","2  Select parts"},{"look","3  Appearance"},{"layout","4  Fit & preview"},{"review","5  Review & apply"},{"share","6  Share"},{"advanced","More tools"}}
local descriptions={
 choose={"Choose your starting point","Start with your current UI, a curated layout, or an import. Nothing changes until you apply."},
 parts={"Keep the parts you want","Unchecked areas keep your current settings. Character actions and bindings are always separate."},
 look={"Make it yours","Choose a coordinated theme and personal readability. Selected values are highlighted."},
 layout={"Fit your screen","Select a frame by name, then nudge it. Try-on hides this panel so you can see the real UI."},
 review={"Review before applying","Check ownership and fit. A restore point is saved before settings change."},
 share={"Take your setup with you","Export your current installed UI or share the draft you have been editing."},
 advanced={"Optional tools","Character actions, capture privacy and restoration are separate from the main setup flow."},
 barshape={"Shape this action bar","Each bar has its own rows, button size and spacing. Actions and bindings stay intact."},
 details={"Fine-tune appearance","These settings are bounded. Meaningful health, warning and selection colors stay intact."}
}
local function text(parent,value,x,y,width,role,color)
 local t=controls.Text(parent,role or "small",value,color);t:SetPoint("TOPLEFT",x,-y);t:SetWidth(width or 444);t:SetJustifyH("LEFT");return t
end
local function action(parent,id,label,x,y,fn,width)
 local b=controls.Button(parent,label,function() fn();studio.RefreshWindow() end)
 b:SetSize(width or 210,30);b:SetPoint("TOPLEFT",x,-y);buttons[id]=b;return b
end
-- Embed the existing Settings dropdown; Studio owns only its staged values and placement.
local selectorRows={}
local function closePicker()
 core.Options.CloseDropdown()
 if window then core.Options.SetFocus(window,nil) end
end
local function selector(parent,id,label,x,y,entries,get,set)
 local caption=text(parent,label,x,y,210)
 if not window.dropdownHost then
  local host=CreateFrame("Frame",nil,window);host:SetAllPoints(window);host:SetFrameStrata("FULLSCREEN_DIALOG");window.dropdownHost=host
 end
 local list={rows={},popupHost=window.dropdownHost,keyboardPanel=window}
 local row=core.Options.CreateRow(parent,{type="dropdown",key=id,label=label,
  values=function()
   local values={};for i,entry in ipairs(type(entries)=="function" and entries() or entries)do
    values[i]={value=entry[1],text=entry[2]}
   end
   return values
  end,
  get=get,set=function(value)set(value);studio.RefreshWindow()end
 },list)
 list.rows[1]=row;selectorRows[#selectorRows+1]=row
 row:SetSize(210,30);row:SetPoint("TOPLEFT",x,-y-20);row.label:Hide()
 local b=row.widget;b:SetSize(210,30);b.label=b.text;b.caption=caption;b.selectorRow=row;buttons[id]=b
 -- Visibility belongs to the complete control row, including its shared focus furniture.
 function b:SetShown(on) row:SetShown(on) end
 refreshers[#refreshers+1]=function()core.Options.RefreshRow(row)end
 core.Options.RefreshRow(row)
 return b
end
local function choices(parent,id,label,y,entries,get,set)
 text(parent,label,0,y)
 local width=(444-(#entries-1)*8)/#entries
 for i,entry in ipairs(entries)do
  local value,caption=entry[1],entry[2]
  local b=controls.Card(parent,width,34,function() set(value);studio.RefreshWindow() end)
  b:SetPoint("TOPLEFT",(i-1)*(width+8),-y-22);text(b,caption,6,8,width-12)
  buttons[id.."-"..tostring(value)]=b
  refreshers[#refreshers+1]=function()b:SetChosen(get()==value)end
 end
end
local function effective() local r=studio.Resolve();return r and r.profile or (studio.Draft and studio.Draft.profile) or {} end
function studio.ShowPage(key)
 if not pages[key] then return nil,"Unknown Studio page" end
 closePicker();currentPage=key
 for name,page in pairs(pages)do page:SetShown(name==key) end
 for name,b in pairs(nav)do b:SetChosen(name==key) end
 local d=descriptions[key];window.pageTitle:SetText(d[1]);window.pageNote:SetText(d[2])
 window.next.label:SetText(key=="review" and "Share setup" or "Continue")
 window.next:SetShown(key~="share" and key~="advanced" and key~="details" and key~="barshape")
 window.back:SetShown(key~="choose");studio.RefreshWindow();return true
end
local function leavePreview()
 studio.Capture(false)
 local ok,reason=studio.ExitPreview()
 if not ok then report(nil,reason);return end
 previewMode=false;if studio.PreviewBar then studio.PreviewBar:Hide() end
 studio.RefreshWindow();window:Show()
end
local function showPreview(scene,capturing)
 closePicker()
 local ok,reason
 if capturing then ok,reason=studio.Capture(true,attribution,privacy)else ok,reason=studio.TryOn(scene)end
 if not ok then report(nil,reason);return end
 if not studio.PreviewBar then
  local bar=CreateFrame("Frame","RikUIStudioPreviewBar",UIParent);studio.PreviewBar=bar
  bar:SetSize(470,56);bar:SetPoint("TOP",0,-16);bar:SetFrameStrata("DIALOG");bar:EnableMouse(true)
  core.Skin.Fill(bar,{0.06,0.07,0.09,1});core.Skin.Outline(bar)
  bar.title=text(bar,"",12,10,285)
  action(bar,"returnPreview","Back to Studio",310,12,leavePreview,146)
  bar:SetScript("OnHide",function()if previewMode then leavePreview() end end)
  if type(UISpecialFrames)=="table" then UISpecialFrames[#UISpecialFrames+1]="RikUIStudioPreviewBar" end
 end
 studio.PreviewBar.title:SetText(capturing and "Capture mode · listed windows hidden" or "Try-on · temporary layout")
 previewMode=true;window:Hide();studio.PreviewBar:SetScale(window:GetScale());studio.PreviewBar:Show()
end
function studio.RefreshWindow()
 if not window then return end
 for _,fn in ipairs(refreshers)do fn() end
 local p=studio.Draft
 window.source:SetText(p and (p.title.." · "..p.creator.." · r"..p.revision) or "Choose a setup")
 if window.checks then for _,check in ipairs(window.checks)do check:Refresh() end end
 local review,reason=studio.Review(accepts)
 window.apply:SetDisabled(not review or #review.fit.conflicts>0)
 window.undo:SetDisabled(#history==0);window.redo:SetDisabled(#redo==0)
 local lines={}
 if review then
  for _,c in ipairs({"appearance","hud","nameplates","group","navigation","inventory","character"})do if studio.Selected[c]then
   lines[#lines+1]=names[c].." — "..tostring((review.fit.effectivePack or p).ownership[c] or p.ownership[c])
  end end
  lines[#lines+1]=""
  lines[#lines+1]=#review.fit.conflicts==0 and "Layout fits. Character clearance is advisory." or "Adjust these frames before applying:"
  for _,c in ipairs(review.fit.conflicts)do lines[#lines+1]=(groupNames[c.key] or c.key)..": "..c.reason end
  for _,c in ipairs(review.fit.warnings or {})do lines[#lines+1]=(groupNames[c.key] or c.key)..": "..c.reason.."; Apply is allowed." end
  lines[#lines+1]=review.reload and "Reload required after Apply for appearance or module changes." or "Geometry applies outside combat."
  for _,c in ipairs(review.conflicts)do lines[#lines+1]="Update "..c.path..": "..(accepts[c.path] and "use creator change" or "keep your edit") end
 else
  local installed=studio.State().installed and pack.Decode(studio.State().installed)
  if studio.LastResult and studio.LastResult.status=="applied" and installed and p and installed.id==p.id and installed.revision==p.revision then
   lines[1]="Setup applied. Your selected settings are saved."
   lines[2]=studio.LastResult.reload and "Reload UI to finish appearance or module changes." or "The layout is ready."
  else lines[1]="Cannot apply: "..tostring(reason)end
 end
 window.details:SetText(table.concat(lines,"\n"))
 core.Scroll.SetContentHeight(window.reviewPane,math.max(230,window.details:GetStringHeight()+12))
 local keys=groupKeys();if groupIndex>#keys then groupIndex=1 end
 buttons.barShape:SetDisabled(not RikUI.LayoutMetrics.IsBar(keys[groupIndex]))
 local fit=studio.Resolve();local conflicts=fit and fit.conflicts or {}
 window.fitStatus:SetText(#conflicts==0 and "No fitting conflicts. Select a sample to see the layout." or (#conflicts.." conflicts: see Review & apply for frame names."))
 for _,id in ipairs({"tryOn","castSample","inventorySample"})do buttons[id]:SetDisabled(not fit or #conflicts>0) end
 window.characterNote:SetText(p and p.character and "Imported character data is available. Review it before running the separate character operation." or "This pack has no character actions or bindings. Export your live bars on the Share page.")
end
local function build()
 window=CreateFrame("Frame","RikUIStudio",UIParent);studio.Window=window
 window:SetSize(680,560);window:SetPoint("CENTER");window:SetFrameStrata("DIALOG");window:EnableMouse(true);window:SetClampedToScreen(true)
 core.Skin.Fill(window,{0.06,0.07,0.09,1});core.Skin.Outline(window)
 text(window,"RikUI Setup Studio",20,18,480,"heading")
 window.source=text(window,"",20,48,620,nil,controls.MUTED)
 action(window,"close","Close",578,16,function()window:Hide()end,82)
 for i,step in ipairs(steps)do
  local key=step[1];local b=controls.Card(window,156,34,function()studio.ShowPage(key)end);nav[key]=b
  b:SetPoint("TOPLEFT",20,-88-(i-1)*42);text(b,step[2],10,9,140)
  local page=CreateFrame("Frame",nil,window);page:SetSize(444,348);page:SetPoint("TOPLEFT",212,-154);pages[key]=page;page:Hide()
 end
 for _,key in ipairs({"details","barshape"})do
  local page=CreateFrame("Frame",nil,window);page:SetSize(444,348);page:SetPoint("TOPLEFT",212,-154);pages[key]=page;page:Hide()
 end
 window.pageTitle=text(window,"",212,88,444,"heading");window.pageNote=text(window,"",212,118,444)
 window.status=text(window,"Edits are staged. Apply changes only on the Review page.",20,510,390)
 window.back=action(window,"back","Back",432,514,function()
  local previous="choose";for i,step in ipairs(steps)do if step[1]==currentPage then previous=steps[math.max(1,i-1)][1] end end
  studio.ShowPage(currentPage=="details" and "look" or currentPage=="barshape" and "layout" or previous)
 end,92)
 window.next=action(window,"next","Continue",534,514,function()
  for i,step in ipairs(steps)do if step[1]==currentPage and steps[i+1]then studio.ShowPage(steps[i+1][1]);break end end
 end,122)
 window.undo=action(window,"undo","Undo",20,418,function()report(studio.DraftUndo(false))end,74)
 window.redo=action(window,"redo","Redo",102,418,function()report(studio.DraftUndo(true))end,74)
 local page=pages.choose
 action(page,"current","Use my current UI",0,0,function()
  local code,why=studio.Export();if code then remember();report(studio.Import(code)) else report(nil,why)end
 end,214)
 action(page,"import","Import a code",230,0,function()
  sharingDialog("Import Setup Pack",nil,function(_,code)local ok,why=studio.Import(code);if ok then studio.ShowPage("parts")end;return ok,why end,"Paste a Setup Pack or legacy UI code. Imports are staged before Apply.","Imported for review.")
 end,214)
 text(page,"Or choose a curated layout",0,50)
 local captions={centered={"Centered","Combat frames close to the action."},classic={"Classic","Familiar corners and bottom bars."},hud={"HUD","A compact central combat display."},healer={"Healer","Room for party and raid frames."}}
 for i,key in ipairs({"centered","classic","hud","healer"})do
  local item=captions[key];local b=controls.Card(page,214,78,function()report(studio.Select(key))end)
  b:SetPoint("TOPLEFT",(i-1)%2*230,-78-math.floor((i-1)/2)*90)
  text(b,item[1],12,10,190,"label");text(b,item[2],12,36,190)
  buttons["choose-"..key]=b
  refreshers[#refreshers+1]=function()b:SetChosen(studio.Draft and studio.Draft.id=="rikui-"..key)end
 end
 text(page,"Continue to choose which areas to adopt.",0,280)
 page=pages.parts;window.checks={}
 selector(page,"recipe","Start with",0,0,{{"everything","All interface parts"},{"appearance","Appearance only"},{"hud","Combat HUD only"},{"group","Party & raid only"},{"navigation","Map & quests only"}},function()
  local count,only=0;for key,on in pairs(studio.Selected)do if on then count=count+1;only=key end end
  return count==6 and "everything" or count==1 and only or "Custom selection"
 end,function(v)remember();studio.Recipe(v)end)
 for i,c in ipairs({"appearance","hud","nameplates","group","navigation","inventory","character"})do
  local key=c;local check=controls.Check(page,430,names[c],function()return studio.Selected[key]==true end,function(on)
   if key=="character" and not studio.Draft.character then report(nil,"This pack contains no character data");return end
   remember();studio.Selected[key]=on;studio.RefreshWindow()
  end);check:SetPoint("TOPLEFT",0,-72-(i-1)*30);window.checks[#window.checks+1]=check
 end
 text(page,"Ownership and reload requirements are shown before Apply.",0,300)
 page=pages.look
 choices(page,"theme","Theme",0,{{"classic","Classic"},{"ocean","Ocean"},{"ink","Ink"}},function()
  local p=effective();return p.theme and (p.theme.accent=="blue" and "ocean" or p.theme.accent=="white" and "ink" or "classic") or "classic"
 end,function(v)remember();studio.Remix();studio.Draft.adjustments=pack.Merge(studio.Draft.adjustments or {},pack.Themes[v])end)
 choices(page,"readability","Personal readability",76,{{"standard","Standard"},{"readable","Readable"},{"contrast","Contrast"},{"calm","Calm"}},function()return studio.State().accessibilityRecipe or studio.Draft.accessibilityRecipe or "standard"end,function(v)report(studio.Accessibility(v))end)
 text(page,"Readable enlarges text and adds labels. Contrast also brightens borders; Calm reduces motion. Personal preferences survive imports.",0,138)
 selector(page,"density","UI size",0,196,{{0.9,"Compact · 90%"},{1,"Standard · 100%"},{1.15,"Roomy · 115%"},{1.3,"Large · 130%"}},function()return effective().scale or 1 end,function(v)report(studio.EditTheme("scale",v))end)
 action(page,"appearanceDetails","Fine-tune appearance",230,216,function()studio.ShowPage("details")end,214)
 text(page,"Font, theme and text-size changes can require a reload after Apply. Try-on previews layout with your currently loaded appearance.",0,278)
 page=pages.details
 for i,spec in ipairs({
  {"accent","Accent",{{"gold","Gold"},{"blue","Blue"},{"white","White"}}},{"border","Border",{{1,"Thin · 1"},{2,"Strong · 2"}}},
  {"texture","Texture",{{"bundled","RikUI texture"},{"flat","Flat"}}},{"font","Font",{{"bundled","RikUI font"},{"game","Game font"}}},
  {"spacing","Spacing",{{"standard","Standard"},{"relaxed","Relaxed"}}}
 })do
  local key=spec[1];selector(page,"detail-"..key,spec[2],(i-1)%2*230,math.floor((i-1)/2)*78,spec[3],function()local p=effective();return key=="font" and p.font or (p.theme or {})[key]end,function(v)report(studio.EditTheme(key,v))end)
 end
 action(page,"backAppearance","Back to appearance",0,258,function()studio.ShowPage("look")end)
 page=pages.layout
 selector(page,"device","Device",0,0,{{"desktop","Desktop"},{"ultrawide","Ultrawide"},{"handheld","Small / handheld"}},function()return studio.Device end,function(v)remember();studio.Device=v;report(true,studio.GamepadLegend())end)
 selector(page,"activity","Activity",230,0,{{"exploration","Exploration"},{"party","Party / dungeon"},{"raid","Raid"},{"town","Town"}},function()return studio.Activity end,function(v)remember();studio.Activity=v;studio.Pinned=true end)
 local pin=controls.Check(page,430,"Keep this activity selected (pin)",function()return studio.Pinned end,function(on)studio.Pinned=on;studio.AutoActivity();studio.RefreshWindow()end);pin:SetPoint("TOPLEFT",0,-64);window.checks[#window.checks+1]=pin
 window.group=selector(page,"group","Frame group · 8-unit snap",0,100,function()
  local entries={};for i,key in ipairs(groupKeys())do entries[#entries+1]={i,groupNames[key] or key}end;return entries
 end,function()return groupIndex end,function(v)groupIndex=v end)
 window.group.selectorRow:SetWidth(444);window.group:SetWidth(444)
 for i,item in ipairs({{"Left",-8,0},{"Right",8,0},{"Up",0,8},{"Down",0,-8}})do action(page,"move-"..item[1],item[1],(i-1)*82,164,function()report(studio.MoveGroup(item[2],item[3]))end,74)end
 action(page,"resetGroup","Reset frame",330,164,function()remember();local key=groupKeys()[groupIndex];if studio.Draft.adjustments and studio.Draft.adjustments.positions then studio.Draft.adjustments.positions[key]=nil end end,114)
 action(page,"barShape","Shape selected bar",0,202,function()
  local key=groupKeys()[groupIndex]
  if not core.LayoutMetrics.IsBar(key) then report(nil,"Select an action, stance or pet bar first");return end
  studio.ShowPage("barshape")
 end,214)
 action(page,"optimizeShapes","Find better bar shapes",230,202,function()
  local resolved,why=studio.Resolve();if not resolved then report(nil,why);return end
  local result=pack.Optimize(resolved.effectivePack or studio.Draft,studio.FitOptions())
  if not result then report(nil,"Could not optimize this setup");return end
  if #result.changes==0 then report(true,"No better shapes found; personal shapes stay intact");return end
  remember();studio.Remix();studio.Draft.adjustments=pack.Merge(studio.Draft.adjustments or {},result.overrides)
  report(true,#result.changes.." bar shapes staged. Undo restores them.")
 end,214)
 window.fitStatus=text(page,"",0,238)
 action(page,"tryOn","Try on layout",0,278,function()showPreview(studio.Activity)end,140)
 action(page,"castSample","Casting sample",152,278,function()showPreview("casting")end,140)
 action(page,"inventorySample","Inventory sample",304,278,function()showPreview("inventory")end,140)
 text(page,"Preview is temporary. Back to Studio restores normal presentation.",0,320)
 page=pages.barshape
 for i,spec in ipairs({{"columns","Buttons per row",1,12},{"size","Button size",24,64},{"spacing","Button spacing",0,16}})do
  local field,label,low,high=unpack(spec)
  selector(page,"shape-"..field,label,0,(i-1)*78,function()
   local entries={};local key=groupKeys()[groupIndex];local max=(field=="columns" and (key=="stance" or key=="pet")) and 10 or high
   for value=low,max do entries[#entries+1]={value,tostring(value)} end;return entries
  end,function()local key=groupKeys()[groupIndex];return pack.BarOptions(key,effective())[field]end,function(value)
   local key=groupKeys()[groupIndex];if not core.LayoutMetrics.IsBar(key) then return end
   remember();studio.Remix();studio.Draft.adjustments=studio.Draft.adjustments or {};studio.Draft.adjustments.barLayout=studio.Draft.adjustments.barLayout or {}
   local options=pack.BarOptions(key,effective());options[field]=value;studio.Draft.adjustments.barLayout[key]=options
  end)
 end
 text(page,"Each action slot remains in order, wrapping left to right. Geometry applies after combat without reloading. Personal bar shapes are kept by optimization.",230,22,214)
 action(page,"backLayout","Back to layout",0,264,function()studio.ShowPage("layout")end)
 page=pages.review
 window.reviewPane=core.Scroll.Create(page);window.reviewPane:SetPoint("TOPLEFT",0,0);window.reviewPane:SetSize(444,232);core.Scroll.Resize(window.reviewPane,444,232)
 window.details=text(window.reviewPane.content,"",0,0,420)
 window.apply=action(page,"apply","Apply setup",0,252,function()report(studio.Apply(accepts))end,214)
 action(page,"reviewFit","Adjust layout",230,252,function()studio.ShowPage("layout")end,214)
 local updateSelector=selector(page,"updateConflict","Creator update conflict",0,290,function()
  local review=studio.Review(accepts);local entries={};for i,c in ipairs(review and review.conflicts or {})do entries[#entries+1]={i,c.path}end
  return #entries>0 and entries or {{0,"No update conflicts"}}
 end,function()local review=studio.Review(accepts);return review and #review.conflicts>0 and conflictIndex or 0 end,function(v)conflictIndex=v end)
 local updateButton=action(page,"updateChoice","Use creator change",230,310,function()
  local review=studio.Review(accepts);local conflict=review and review.conflicts[conflictIndex]
  if conflict then accepts[conflict.path]=not accepts[conflict.path];report(true,conflict.path..": "..(accepts[conflict.path] and "use creator change" or "keep your edit"))end
 end,214)
 refreshers[#refreshers+1]=function()
  local review=studio.Review(accepts);local conflict=review and review.conflicts[conflictIndex]
  local has=review and #review.conflicts>0 or false
  updateSelector:SetShown(has);updateSelector.caption:SetShown(has);updateButton:SetShown(has)
  updateButton:SetDisabled(not conflict);updateButton.label:SetText(conflict and accepts[conflict.path] and "Keep my edit" or "Use creator change")
 end
 page=pages.share
 text(page,"Current installed setup",0,0,444,"label");text(page,"Use this to edit your real UI on rikwow.com/studio.",0,24)
 action(page,"exportLive","Export live",0,54,function()local code,why=studio.Export();if code then sharingDialog("Export current setup",code,nil,"Copy the entire code into rikwow.com/studio. Supported settings only; no private records.")else report(nil,why)end end,214)
 text(page,"Your Studio draft",0,112,444,"label");text(page,"Share the staged parts, or just the coordinated theme.",0,136)
 action(page,"shareDraft","Share draft",0,166,function()
  local value=pack.Copy(studio.Draft);value.components=pack.Copy(studio.Selected);if not value.components.character then value.character=nil end
  local code,why=pack.Encode(value);if code then sharingDialog("Share Setup Pack",code,nil,"Edit or create a shareable link at rikwow.com/studio.")else report(nil,why)end
 end,214)
 action(page,"themeExport","Export theme",230,166,function()local code,why=studio.ThemeExport();if code then sharingDialog("Share theme",code,nil,"Appearance-only Setup Pack.")else report(nil,why)end end,214)
 text(page,"Optional character export",0,222,444,"label")
 action(page,"exportBars","Export bars",0,252,function()local code,why=studio.ExportCharacter();if code then sharingDialog("Export live standard bars",code,nil,"Five standard pages and referenced macros. Bindings excluded.")else report(nil,why)end end,214)
 action(page,"exportKeys","Export bars + keys",230,252,function()local code,why=studio.ExportCharacter(nil,true);if code then sharingDialog("Export bars and main keys",code,nil,"Includes ACTIONBUTTON1..12 bindings. Review before sharing.")else report(nil,why)end end,214)
 page=pages.advanced
 action(page,"restore","Restore last change",0,0,function()report(studio.Restore())end,214)
 action(page,"integration","QuestTogether recipe",230,0,function()report(studio.IntegrationRecipe())end,214)
 text(page,"Restoration has 3 bounded slots. Export a backup before client restart.",0,44)
 window.characterNote=text(page,"",0,86)
 action(page,"character","Review character setup",0,142,function()report(studio.PrepareCharacter())end,214)
 action(page,"bindings","Apply selected bindings",230,142,function()report(studio.ApplyBindings())end,214)
 text(page,"Capture privacy · only the listed windows",0,194,444,"label")
 for i,area in ipairs({"chat","planner","inventory"})do
  local check=controls.Check(page,140,"Hide "..area,function()return privacy[area]end,function(on)privacy[area]=on end)
  check:SetPoint("TOPLEFT",(i-1)*148,-222);window.checks[#window.checks+1]=check
 end
 local credit=controls.Check(page,214,"Show pack attribution",function()return attribution end,function(on)attribution=on end);credit:SetPoint("TOPLEFT",0,-256);window.checks[#window.checks+1]=credit
 action(page,"capture","Enter capture mode",230,250,function()showPreview(nil,true)end,214)
 text(page,"Names, world imagery and other addons remain visible. Back to Studio restores the hidden windows.",0,300)
 core.Options.EnableKeyboard(window,function()
  local visible={};for _,row in ipairs(selectorRows)do if row:IsVisible() and row.widget:IsVisible() then visible[#visible+1]=row end end
  return visible
 end)
 window.MovePage=function(delta)
  for i,step in ipairs(steps)do if step[1]==currentPage then
   studio.ShowPage(steps[math.max(1,math.min(#steps,i+delta))][1]);return true
  end end
  return false
 end
 window:SetScript("OnHide",function()closePicker();if not previewMode then studio.Capture(false);studio.ExitPreview()end end)
 if type(UISpecialFrames)=="table" then UISpecialFrames[#UISpecialFrames+1]="RikUIStudio" end
 studio.ShowPage("choose")
end
function studio.Open()
 if InCombatLockdown() then return nil,"Open Setup Studio out of combat" end
 if not core.Profile then return nil,"Still loading" end
 local issue
 if not studio.Draft then
  local code,why=studio.Export()
  if code then studio.Import(code)else studio.Select("centered");issue=why end
 end
 if not window then build()end
 local screen=core.Layout.Screen();window:SetScale(math.min(1,(screen.width-16)/680,(screen.height-16)/560))
 studio.RefreshWindow();window:Show()
 if issue then window.status:SetText("Current UI could not be staged: "..tostring(issue))end
 return true
end
-- Studio remains available to development fixtures; public entry is paused.
function studio.Command(args)
 if args=="" then report(studio.Open())
 elseif args=="exit" then if previewMode then leavePreview()else studio.ExitPreview();studio.Capture(false)end
 elseif args:match("^accept ")then accepts[args:sub(8)]=true;studio.RefreshWindow()
 elseif args:match("^restore ")then report(studio.Restore(tonumber(args:sub(9))))
 else core:Print("Usage: /rik studio [exit|accept <conflict path>|restore <1..3>]")end
end
