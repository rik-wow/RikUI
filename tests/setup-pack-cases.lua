-- Shared executable cases run against LuaJIT and the exact browser Lua sources.
function RikUI.SetupPack.Conformance()
    local p=RikUI.SetupPack
    local sample={version=1,id="sample",revision=1,title="Sample",creator="RikUI",components={hud=true},ownership={hud="rikui"},
        viewport={width=1920,height=1080},profile={scale=1,positions={main={point="BOTTOM",relativePoint="BOTTOM",x=0,y=40},
        target={point="BOTTOM",relativePoint="BOTTOM",x=0,y=40}}},groups={main={component="hud",width=500,height=90,priority=1},
        target={component="hud",width=200,height=70,priority=2}}}
    local code=assert(p.Encode(sample)); assert(p.Equal(assert(p.Decode(code)),sample))
    local fitted=assert(p.Resolve(sample,{viewport={width=1280,height=720}}))
    assert(#fitted.conflicts==0); assert(p.Equal(fitted,assert(p.Resolve(sample,{viewport={width=1280,height=720}}))))
    assert(sample.profile.positions.main.point=="BOTTOM")
    local personal={positions={target={point="BOTTOMLEFT",relativePoint="BOTTOMLEFT",x=-200,y=0}}}
    local bad=assert(p.Resolve(sample,{overrides=personal})); assert(#bad.conflicts>0)
    local readable=assert(p.Resolve(sample,{accessibility={scale=1.3,reducedMotion=true,nonColor=true}}))
    assert(readable.profile.scale==1.3 and readable.profile.reducedMotion and readable.profile.showHotkeys)
    local update=p.Update({scale=1,font="bundled"},{scale=1.2,font="game"},{scale=1.1,font="bundled"})
    assert(update.profile.scale==1.1 and update.profile.font=="game" and #update.conflicts==1)
    assert(p.Update({scale=1},{scale=1.2},{scale=1.1},{scale=true}).profile.scale==1.2)
    local invalid=p.Copy(sample); invalid.profile.chatHistory={"secret"}; assert(not p.Validate(invalid))
    invalid=p.Copy(sample); invalid.version=2; assert(not p.Validate(invalid))
    invalid=p.Copy(sample); invalid.profile.scale=0/0; assert(not p.Validate(invalid))
    invalid=p.Copy(sample); invalid.groups.main.priority=1.2; assert(not p.Validate(invalid))
    invalid=p.Copy(sample); invalid.activities={raid={font="game"}}; assert(not p.Validate(invalid))
    invalid=p.Copy(sample); invalid.ancestry={id="bad",revision=0,creator="RikUI"}; assert(not p.Validate(invalid))
    assert(not p.Decode(code:sub(1,-2).."X"))
    local legacy=assert(RikUI.Sharing.Encode("profile",{scale=1.1,modules={chat=false}}))
    assert(p.Import(legacy).profile.modules.chat==false)
    local retired=p.Copy(sample);retired.profile.modules={classcooldowns=false,cooldownviewer=true,cooldowns=false}
    local canonical=assert(p.Decode(assert(p.Encode(retired))))
    assert(canonical.profile.modules.classcooldowns==nil and canonical.profile.modules.cooldownviewer==nil and canonical.profile.modules.cooldowns==false)
    assert(retired.profile.modules.classcooldowns==false)
    local center=p.CharacterArea(sample.viewport)
    local override={positions={target={point="BOTTOMLEFT",relativePoint="BOTTOMLEFT",x=900,y=520}}}
    local obstructed=assert(p.Resolve(sample,{overrides=override}))
    assert(obstructed.profile.positions.target.x==900 and obstructed.profile.positions.target.y==520)
    assert(obstructed.conflicts[1].reason=="Obstructs character viewing area")
    assert(obstructed.groups[1].key=="Character viewing area")
    assert(center.x+center.width/2==960 and center.y+center.height/2==540)
    local floating=p.Copy(sample);floating.groups.target.floating=true
    assert(#assert(p.Resolve(floating,{overrides=override})).conflicts==0)
    local cyclic={};cyclic.self=cyclic;assert(not p.Validate(cyclic))
    local choices=p.ModuleChoices();assert(#choices==46)
    local moduleSample=p.Copy(sample);moduleSample.profile.modules={bars=false}
    local off=assert(p.Resolve(moduleSample,{overrides={positions={main={point="BOTTOMLEFT",relativePoint="BOTTOMLEFT",x=-1000,y=-1000}}}}))
    assert(#off.disabledGroups==1 and off.disabledGroups[1].key=="main")
    assert(off.profile.positions.main.x==-1000 and #off.conflicts==0)
    assert(not p.GroupEnabled("main",off.profile) and p.GroupEnabled("target",off.profile))
    local blocked=assert(p.Resolve(sample,{overrides={modules={unitframes=false,unitauras=true}}}))
    assert(not p.ModuleEnabled(blocked.profile,"unitauras") and #blocked.disabledGroups==1)
    local flags=assert(p.SetModule({modules={unitframes=false}},"unitauras",true))
    assert(flags.modules.unitframes and flags.modules.unitauras)
    assert(not p.SetModule({},"unknown",true) and not p.SetModule({},"chat","on"))
    local shapes=p.Copy(sample)
    shapes.profile.positions.main={point="BOTTOMLEFT",relativePoint="BOTTOMLEFT",x=64,y=64}
    shapes.profile.positions.target={point="BOTTOMLEFT",relativePoint="BOTTOMLEFT",x=64,y=64}
    shapes.groups.main={component="hud",width=498,height=36,priority=1,native=true}
    shapes.groups.target.priority=100
    local configured=assert(p.Resolve(shapes,{overrides={barLayout={main={columns=4,size=42,spacing=2}},positions={target={point="BOTTOMLEFT",relativePoint="BOTTOMLEFT",x=64,y=64}}}}))
    local main,target
    for _,g in ipairs(configured.groups)do if g.key=="main" then main=g elseif g.key=="target" then target=g end end
    assert(main.rect.width==174 and main.rect.height==130 and main.geometry.grid.rows==3)
    assert(target.rect.x==64 and target.rect.y==64 and target.fixed and #configured.conflicts==0)
    assert(not p.Equal(main.rect,target.rect) and shapes.profile.positions.main.x==64)
    local padding=assert(p.Resolve(shapes,{overrides={gryphons=true}}))
    for _,g in ipairs(padding.groups)do if g.key=="main" then
        assert(g.rect.width==674 and g.bodyRect.width==498 and g.bodyRect.x-g.rect.x==88)
        assert(padding.profile.positions.main.x==g.bodyRect.x)
    end end
    local narrow=p.Copy(sample);narrow.viewport={width=640,height=360}
    narrow.groups={bar4={component="hud",width=36,height=498,priority=1,native=true}}
    narrow.profile.positions={bar4={point="BOTTOMLEFT",relativePoint="BOTTOMLEFT",x=600,y=8}}
    local original=assert(p.Encode(narrow))
    local optimized=assert(p.Optimize(narrow))
    assert(#optimized.fit.conflicts==0 and #optimized.changes==1 and optimized.attempts<=5)
    assert(optimized.changes[1].key=="bar4" and original==p.Encode(narrow))
    local retained=assert(p.Optimize(narrow,{overrides={barLayout={bar4={columns=1}}}}))
    assert(#retained.changes==0 and #retained.fit.conflicts>0)
    local again=assert(p.Resolve(narrow,{overrides=optimized.overrides}))
    assert(p.Equal(again,optimized.fit))
    return {geometry=RikUI.Codec.Encode(configured,true),optimized=RikUI.Codec.Encode(optimized,true),modules=RikUI.Codec.Encode({choices=choices,off=off,blocked=blocked,flags=flags},true),canonical=assert(p.Encode(canonical)),code=code,fitted=RikUI.Codec.Encode(fitted,true),readable=RikUI.Codec.Encode(readable,true),update=RikUI.Codec.Encode(update,true)}
end
