return function(check)
    local saved = RikUI
    RikUI = {}; assert(loadfile("src/core/layout-metrics.lua"))()
    local m=RikUI.LayoutMetrics
    for _, columns in ipairs({1,3,4,5,6,12}) do
        for _, size in ipairs({24,36,64}) do
            for _, gap in ipairs({0,6,16}) do
                local grid=m.Grid(12,{columns=columns,size=size,spacing=gap})
                check("grid bounds cover every button "..columns..":"..size..":"..gap,
                    grid.width==columns*size+(columns-1)*gap and grid.height==math.ceil(12/columns)*size+(math.ceil(12/columns)-1)*gap)
                for i=1,12 do
                    local x,y=m.Cell(i,grid)
                    check("grid cell stays inside bounds",x>=0 and x+size<=grid.width and -y+size<=grid.height)
                end
            end
        end
    end
    for _, value in ipairs({ {columns=0}, {columns=13}, {size=23}, {size=65}, {spacing=-1}, {spacing=17}, {columns=1.5}, {run="code"} }) do
        check("invalid bar settings rejected",not m.ValidateBar(value,"main"))
    end
    local group={width=498,height=36,native=true}
    local shape=m.Measure("main",{barLayout={main={columns=4,size=42,spacing=2}}},group,{})
    check("configured bar has exact body",shape.width==174 and shape.height==130)
    local custom=m.Measure("main",{}, {width=123,height=45},{})
    check("legacy custom rectangle preserved",custom.width==123 and custom.height==45)
    local cast=m.Measure("castplayer",{castbars={widthScale=1.5,height=36}},{width=280,height=22,native=true},{})
    check("cast dimensions shared",cast.width==420 and cast.height==36)
    local chat=m.Measure("chat",{chat={size={width=600,height=240}}},{width=438,height=214},{})
    check("chat includes its chrome",chat.width==608 and chat.height==318)
    local bags=m.Measure("bags",{bags={columns=16}},{width=394,height=362},{bags={columns=10}})
    check("bag columns preserve observed slot capacity",bags.width==622 and bags.height==324 and bags.kind=="content")
    local unchanged=m.Measure("bags",{bags={columns=10}},{width=420,height=540},{})
    check("unchanged custom inventory observation remains exact",unchanged.height==540)
    local xp=m.Measure("xpbar",{xpbar={compact=false}},{width=498,height=8},{})
    check("missing defaults do not enlarge a progress row",xp.height==8)
    local two=m.Measure("xpbar",{xpbar={compact=true}},{width=498,height=32},{xpbar={compact=false}})
    check("compact XP and reputation rows account for both rows",two.height==18)
    local gryphons=m.Measure("main",{gryphons=true},group,{})
    check("gryphons extend padding without moving body",gryphons.width==498 and gryphons.padding.left==88 and gryphons.padding.bottom==12)
    RikUI=saved
end
