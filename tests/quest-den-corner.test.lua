-- Four consecutive filtered v6 surfaces from the recorded Grizzled Den correction.
return function(check)
    local previousRikUI=RikUI
    RikUI={};RikUI["Secret"]={IsSecret=function()return false end}
    local ok,reason=pcall(function()
        dofile("src/modules/questplanner/quest-schema.lua")
        dofile("src/modules/questplanner/quest-nav-geometry.lua")
        local geometry=RikUI.QuestPlanner.NavGeometry
        local surfaces={
            {{-319.4165,371.7964,-5666.1665},{-318.9165,371.9964,-5665.4165},{-312.6665,370.8965,-5666.1665},{-312.6665,370.0964,-5668.9165}},
            {{-320.4165,371.7964,-5666.4165},{-319.4165,371.7964,-5666.1665},{-312.6665,370.0964,-5668.9165},{-310.4165,369.1964,-5672.4165}},
            {{-312.6665,370.0964,-5668.9165},{-311.4165,369.5964,-5670.4165},{-310.4165,369.1964,-5672.4165}},
            {{-309.9165,369.5964,-5670.9165},{-310.4165,369.1964,-5672.4165},{-311.4165,369.5964,-5670.4165}},
        }
        local gates={
            {{-312.6665,370.0964,-5668.9165},{-319.4165,371.7964,-5666.1665}},
            {{-312.6665,370.0964,-5668.9165},{-310.4165,369.1964,-5672.4165}},
            {{-311.4165,369.5964,-5670.4165},{-310.4165,369.1964,-5672.4165}},
        }
        local origin={-312.682137775,370.11083435,-5668.87405375}
        local endpoint={-311.392283612,0,-5670.4499804}
        endpoint[2]=assert(geometry.Height(surfaces[4],endpoint[1],endpoint[3]))
        local route={corridor={6041618,6041715,6041617,6041611},surfaces=surfaces,portals={},points={origin}}
        for i,surface in ipairs(surfaces) do
            local center={0,0,0}
            for _,point in ipairs(surface)do for axis=1,3 do center[axis]=center[axis]+point[axis]/#surface end end
            route.points[#route.points+1]=center
            if gates[i] then
                local left,right=gates[i][1],gates[i][2]
                local mid=geometry.Midpoint(left,right)
                route.portals[i]={left=left,right=right,midpoint=mid,to=route.corridor[i+1]}
                route.points[#route.points+1]=mid
            end
        end
        route.points[#route.points+1]=endpoint
        local old={-312.652586449,0,-5668.97280182}
        old[2]=assert(geometry.Height(surfaces[2],old[1],old[3]))
        local previous={point=old,index=2,origin={-312.725142359,370.158377446,-5668.73035056}}
        local aim,proof,last=geometry.CorridorAim(route,origin,1,previous)
        assert(aim and proof and last,"connected corner needs a proved aim")
        assert(geometry.Contains(surfaces[last],aim[1],aim[3]),"aim left its connected floor")
        local dx,dz=aim[1]-origin[1],aim[3]-origin[3]
        assert(dx>0 and dz<0,"tiny corner introduced a one-frame left correction")
        assert(dx*dx+dz*dz>.15*.15,"corner aim is shorter than one replay step")
    end)
    RikUI=previousRikUI
    check("actual Den tiny-corner continuation",ok,reason)
end
