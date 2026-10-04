RikUI={Presets={},Modules={},RegisterCommand=function() end,RegisterEvent=function() end,Secret={IsSecret=function()return false end},
    Runtime={},Changed=function() end,Setup={IsApplying=function()return false end,IsUndoing=function()return false end}}
for _,file in ipairs({"src/core/layout-metrics.lua","src/core/profile-schema.lua","src/persistence/codec.lua","src/setup/setup.lua","src/setup/preset-schema.lua","src/setup/setup-pack.lua","data/layouts.lua","src/setup/setup-pack-library.lua","src/configuration/options/sharing.lua"}) do dofile(file) end
RikUI.Setup.IsApplying=function()return false end;RikUI.Setup.IsUndoing=function()return false end
local memory,failSave={},false
RikUI.Store={Available=function()return true end,Load=function(key)return memory[key] end,
    Save=function(key,value)if failSave then return false,"injected write failure" end
    local encoded=RikUI.Codec.Encode(value,true);if not encoded then return false,"capacity" end
    memory[key]=RikUI.Codec.Decode(encoded);return true end}
local applied=0;local frameFail=false;local combat=false
InCombatLockdown=function()return combat end
RikUI.Layout={Groups={},Screen=function()return {width=1920,height=1080} end,Apply=function()applied=applied+1;if frameFail then error("injected refresh failure") end end}
RikUI.Combat={Queue=function(f)if not combat then f() end;return true end}
RikUI.CharDB={profile="Default"}
RikUI.Profile={scale=1,font="bundled",textScale=1,reducedMotion=false,modules={chat=true},positions={},chat={fontSize=14},questtracker={collapsed=false}}
dofile("src/setup/setup-studio.lua")
local chatRefreshes=0;RikUI.Chat={enabled=true,Restore=function()chatRefreshes=chatRefreshes+1 end}
local s,p=RikUI.Studio,RikUI.SetupPack
local function sample(revision)
 return {version=1,id="runtime",revision=revision,title="Runtime",creator="RikUI",profile={scale=1,font="bundled",chat={fontSize=18},positions={main={point="BOTTOM",relativePoint="BOTTOM",x=0,y=40}}},
    viewport={width=1920,height=1080},groups={main={component="hud",width=498,height=36,priority=1}},
    components={hud=true,appearance=true},ownership={hud="rikui",appearance="rikui"},devices={handheld={scale=1.15}},
    activities={raid={questtracker={collapsed=true}}}}
end
local checks=0
local function check(ok,label)assert(ok,label);checks=checks+1 end
check(s.Import(assert(p.Encode(sample(1)))),"stage import")
check(RikUI.Profile.chat.fontSize==14,"import never applies")
s.Selected={hud=true}
check(s.Apply(),"selective apply")
check(RikUI.Profile.chat.fontSize==14,"unselected appearance preserved")
check(s.State().installed~=nil and s.State().applied~=nil,"separate creator source retained")
check(s.Restore(),"restore successful")
check(next(RikUI.Profile.positions)==nil,"restoration removes newly created group anchors")
check(s.Accessibility("contrast"),"personal accessibility recipe")
s.Selected={hud=true,appearance=true};check(s.Apply(),"apply accessibility")
check(RikUI.Profile.textScale==1.15 and RikUI.Profile.reducedMotion,"accessibility wins")
check(s.State().accessibility.contrast,"preferences kept outside pack")
local incoming=sample(2);incoming.profile.chat.fontSize=20
RikUI.Profile.chat.fontSize=21
check(s.Import(assert(p.Encode(incoming))),"stage update")
local review=assert(s.Review())
check(#review.conflicts>=1 and review.profile.chat.fontSize==21,"three way update preserves personal edit")
check(s.Apply({["chat.fontSize"]=true}),"accept creator field")
check(RikUI.Profile.chat.fontSize==20,"selective update applied")
check(chatRefreshes>0,"owned chat resizes before validated geometry applies")
check(s.Restore(),"update restoration")
check(RikUI.Profile.chat.fontSize==21,"restore returns actual pre-update personal value")
failSave=true
local before=p.Copy(RikUI.Profile);check(not s.Apply(),"storage failure refuses writes")
check(p.Equal(before,RikUI.Profile),"failed storage did not change UI")
failSave=false;frameFail=true
check(not s.Apply({["chat.fontSize"]=true}),"frame refresh failure reported")
check(s.LastResult.status=="partial" and #s.LastResult.changed>0,"partial result records settings already changed")
frameFail=false;check(s.Restore(),"partial application recovered")
combat=true;check(not s.Import(assert(p.Encode(sample(3)))),"combat import refused")
check(not s.Apply(),"combat apply refused");combat=false
IsAddOnLoaded=function()return false end
check(not s.IntegrationAvailable(),"missing optional addon safe")
check(s.IntegrationRecipe(),"missing integration recipe does not mutate foreign settings")
check(s.Draft.ownership.nameplates~= "specialist","missing optional addon keeps RikUI ownership")
IsAddOnLoaded=function()error("optional api failed")end
check(not s.IntegrationAvailable(),"optional integration failure safe")
check(type(s.GamepadLegend())=="string","unavailable controller API has honest fallback")
for _,name in ipairs({"centered","classic","hud","healer"})do local b=assert(p.Bundled(name));check(p.Validate(b)~=nil,"bundled pack validates") end
check(s.Accessibility("standard"),"reset accessibility")
check(s.Import(assert(p.Encode(sample(3)))),"install presentation fixture")
check(s.Apply(),"apply presentation fixture")
local original=assert(p.Encode(assert(p.Decode(s.State().installed))))
local starting=p.Copy(RikUI.Profile.positions.main)
for i=1,4 do check(s.Presentation("raid","handheld",true),"handheld transition");check(s.Presentation("exploration","desktop",true),"desktop transition") end
check(p.Equal(starting,RikUI.Profile.positions.main),"repeated presentations have no drift")
check(original==s.State().installed,"presentations leave creator source unchanged")
RikUI.Profile.positions.main.x=RikUI.Profile.positions.main.x+8
local personalPosition=p.Copy(RikUI.Profile.positions.main)
s.Presentation("raid","handheld",true);s.Presentation("exploration","desktop",true)
check(p.Equal(personalPosition,RikUI.Profile.positions.main),"personal position survives presentation changes")
local normal=p.Copy(RikUI.Profile)
check(s.TryOn("exploration"),"enter try-on")
check(p.Equal(normal,RikUI.Profile),"try-on never changes persisted profile")
check(s.ExitPreview(),"exit try-on")
check(p.Equal(normal,RikUI.Profile),"try-on restores presentation")
local badOptions={};badOptions.overrides=badOptions
check(not p.Resolve(sample(1),badOptions),"cyclic options rejected")
check(not p.Resolve(sample(1),{accessibility={scale="large"}}),"invalid personal recipe rejected")
local owners=sample(1);owners.ownership.hud="stock"
local adopted=p.Adopt(normal,owners.profile,owners,{hud=true},{})
check(adopted.interfaceOwners.hud=="stock" and adopted.modules.unitframes,"shared group frames remain owned when HUD is stock")
failSave=true;local beforePresentation=p.Copy(RikUI.Profile)
s.Presentation("town","handheld",true)
check(p.Equal(beforePresentation,RikUI.Profile),"presentation storage failure leaves settings unchanged")
check(s.PresentationIssue and s.PresentationIssue:match("save failed"),"presentation storage error is visible")
failSave=false
local off=sample(1);off.profile.modules={unitframes=false};off.components.group=true;off.ownership.group="rikui"
check(not p.Adopt(normal,off.profile,off,off.components,{}).modules.unitframes,"explicit unitframe off choice is respected")
local absent=sample(4);absent.integration="questtogether";absent.ownership.nameplates="specialist";absent.components.nameplates=true;absent.profile.modules={nameplates=false}
check(s.Import(assert(p.Encode(absent))),"import optional specialist pack")
check(s.Resolve().effectivePack.ownership.nameplates=="rikui","imported specialist pack falls back to RikUI when absent")
check(s.Resolve().profile.modules.nameplates,"absence fallback enables RikUI nameplates")
check(s.Draft.ownership.nameplates=="specialist","fallback preserves original creator ownership")
local selective=p.Adopt({presentation={hidden={bar4=false}}},{presentation={hidden={bar4=true,chat=true}}},s.Draft,{appearance=true},{})
check(selective.presentation.hidden.bar4==false and selective.presentation.hidden.chat,"presentation only changes adopted components")
local shown={chat=true,planner=true}
ChatFrame1={IsShown=function()return shown.chat end,Hide=function()shown.chat=false end,Show=function()shown.chat=true end}
RikUIQuestPlannerWindow={IsShown=function()return shown.planner end,Hide=function()shown.planner=false end,Show=function()shown.planner=true end}
check(s.Capture(true,false,{chat=true}),"capture privacy selection")
check(not shown.chat and shown.planner,"only explicitly chosen capture regions hidden")
check(s.Capture(false),"capture exit")
check(shown.chat and shown.planner,"normal visibility restored")
check(s.Import(assert(p.Encode(sample(5)))) and s.Apply(),"install restoration failure fixture")
frameFail=true;check(not s.Restore(),"restore refresh failure is reported")
check(s.LastResult.status=="partial" and #s.LastResult.changed>0,"restore records actual completed writes")
frameFail=false;check(s.Restore(),"partial restoration can be retried safely")
local modes=sample(6);modes.devices.handheld.presentation={hidden={bar4=true,chat=true}}
check(s.Import(assert(p.Encode(modes))),"install hidden presentation fixture")
check(s.Apply(),"apply hidden presentation fixture")
check(s.Presentation("exploration","handheld",true),"hide handheld companions")
check(RikUI.Profile.presentation.hidden.bar4,"handheld companion hidden")
check(s.Presentation("exploration","desktop",true),"return desktop presentation")
check(not (RikUI.Profile.presentation and RikUI.Profile.presentation.hidden and RikUI.Profile.presentation.hidden.bar4),"desktop removes prior hidden override")
RikUI.WizardControls={}
dofile("src/configuration/options/setup-studio-view.lua")
local edited=sample(7);edited.adjustments={positions={main={point="BOTTOMLEFT",relativePoint="BOTTOMLEFT",x=480,y=64}}}
check(s.Import(assert(p.Encode(edited))),"import existing browser adjustment")
check(s.MoveGroup(8,0),"native adjustment of imported position")
check(s.Draft.adjustments.positions.main.x==488,"native move edits the effective adjustment")
check(s.Draft.profile.positions.main.x==0,"native move preserves creator geometry")
local extraShown=true
ChatFrame2={IsShown=function()return extraShown end,Hide=function()extraShown=false end,Show=function()extraShown=true end}
check(s.Capture(true,false,{chat=true}),"capture covers additional chat windows")
check(not extraShown,"additional chat window hidden")
check(s.Capture(false) and extraShown,"additional chat window restored")
-- Live frames resolve partial persisted anchors from layout defaults; exports must do the same.
RikUI.Layout.Groups.main={frames={{GetWidth=function()return 498 end,GetHeight=function()return 36 end}}}
RikUI.Layout.GetPosition=function()return {point="BOTTOM",relativePoint="BOTTOM",x=32,y=40} end
RikUI.Layout.Floats=function()return false end
RikUI.Profile.positions.main={x=32}
local exported,exportCode=pcall(s.Export)
check(exported and type(exportCode)=="string","live export normalizes partial persisted anchors")
check(RikUI.Profile.positions.main.point==nil,"export does not rewrite stored source anchors")
local decoded=assert(p.Decode(exportCode))
check(decoded.profile.positions.main.relativePoint=="BOTTOM","portable anchor is complete")
RikUI.Profile.modules.geargoals=false
local gearExport=assert(p.Decode(assert(s.Export())))
check(gearExport.profile.modules.geargoals==false,"gear module preference survives live export")
RikUI.Profile.modules.classcooldowns=false;RikUI.Profile.modules.cooldownviewer=true;RikUI.Profile.modules.cooldowns=false
local migrated=assert(p.Decode(assert(s.Export())))
check(migrated.profile.modules.classcooldowns==nil and migrated.profile.modules.cooldownviewer==nil,"retired flags do not block live export")
check(migrated.profile.modules.cooldowns==false,"current cooldown preference is preserved")
check(RikUI.Profile.modules.classcooldowns==false,"migration never rewrites live profile")
local old=p.Copy(migrated);old.profile.modules.classcooldowns=true
local legacy=assert(p.Import(assert(RikUI.Sharing.Encode("profile",old.profile))))
check(legacy.profile.modules.classcooldowns==nil,"legacy UI imports canonicalize retired flags")
old.profile.modules.unregistered=true
check(not p.Validate(old),"unknown active modules remain rejected")
RikUI.Profile.positions.main={point="BOTTOMLEFT",relativePoint="BOTTOMLEFT",x=32,y=40}
local center=sample(8);center.id="center-advisory";center.adjustments={positions={main={point="BOTTOMLEFT",relativePoint="BOTTOMLEFT",x=720,y=520}}}
check(s.Import(assert(p.Encode(center))),"stage character advisory")
local advisory=assert(s.Review());check(#advisory.fit.conflicts==0 and #advisory.fit.warnings>0,"character guidance does not block review")
check(s.Apply(),"character advisory allows actual Apply")
check(RikUI.Profile.positions.main.x==720 and RikUI.Profile.positions.main.y==520,"Apply preserves deliberate center position")
check(s.Restore(),"advisory apply remains restorable")
local blocked=p.Copy(center);blocked.revision=9;blocked.adjustments.positions.main.x=-20
check(s.Import(assert(p.Encode(blocked))),"stage genuine invalid placement")
check(#assert(s.Review()).fit.conflicts>0 and not s.Apply(),"off-screen placement still blocks Apply")
print("OK: "..checks.." Studio lifecycle checks")
