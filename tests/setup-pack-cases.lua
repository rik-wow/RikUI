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
    return {canonical=assert(p.Encode(canonical)),code=code,fitted=RikUI.Codec.Encode(fitted,true),readable=RikUI.Codec.Encode(readable,true),update=RikUI.Codec.Encode(update,true)}
end
