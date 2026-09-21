-- Actual native widget calls recorded by the stub; no claim of native rendering.
return function(check,p,env,canvas,arrow)
    local old={CreateFrame,Minimap,C_Minimap,GetCVarBool,GetPlayerFacing,p.Terrain,p.Context.Position}
    local geometry=p.NavGeometry
    local clipped=geometry.ScreenAnts({{-100,100},{300,100}},200,200,0,96,false)
    check("offscreen endpoints retain visible crossing",#clipped>10 and clipped[1][1]>=3 and clipped[#clipped][1]<=197)
    check("circle excludes rectangular corners",#geometry.ScreenAnts({{3,3},{30,3}},200,200,0,96,true)==0)
    check("dot pool bound enforced",#geometry.ScreenAnts({{0,100},{20000,100}},20000,200,0,96,false)==96)
    local positionTest={mapID=1426,x=.5,y=.5}
    local hint=p.Guidance.Instruction({next={mapID=1426,x=.4,y=.5}},positionTest,0,1000,1000)
    check("west aim requires left turn",hint.text:find("Turn left",1,true))
    hint=p.Guidance.Instruction({next={mapID=1426,x=.6,y=.5}},positionTest,nil,1000,1000)
    check("missing facing uses explicit compass direction",hint.text:find("Head E",1,true))
    check("different map cannot supply instruction",not p.Guidance.Instruction({next={mapID=1,x=.6,y=.5}},positionTest,0,1000,1000))
    local dots={}
    CreateFrame=function(...)
        local frame=old[1](...)
        local create=frame.CreateTexture
        frame.CreateTexture=function(self,...)
            local dot=create(self,...);dots[#dots+1]=dot;return dot
        end
        return frame
    end
    Minimap=CreateFrame("Frame",nil,UIParent);Minimap:SetSize(200,200);Minimap:Show()
    local radius,rotates,facing=100,false,0
    C_Minimap={GetViewRadius=function() return radius end,IsRotateMinimapIgnored=function() return false end}
    GetCVarBool=function() return rotates end;GetPlayerFacing=function() return facing end
    local position={mapID=1426,x=.45,y=.5}
    p.Context.Position=function() return position end
    local route={next={mapID=1426,x=.49,y=.5},meters=80,seconds=12,
        points={{mapID=1426,x=.45,y=.5},{mapID=1426,x=.49,y=.5}}}
    p.Terrain={Invalidate=function() end,Guidance=function() return route end,Status=function() return {status="modeled"} end}
    p.Command("show");p.Navigation.Refresh()
    local summary=p.View.Window.summary
    check("tracker shows live direction and distance",summary.status:GetText():find("Turn right",1,true)
        and summary.status:GetText():find("80 yd",1,true))
    check("arrow shares useful instruction",arrow.label:GetText()==summary.status:GetText())
    local function visible(parent)
        local result={}
        for _,dot in ipairs(dots) do if dot:IsShown() and dot.parent:GetParent()==parent then result[#result+1]=dot end end
        return result
    end
    local world,mini=visible(canvas),visible(Minimap)
    check("world map and minimap both render route ants",#world>0 and #mini>0)
    local oldX=world[1].point[4]
    for _,driver in ipairs(env.frames) do if driver.scripts.OnUpdate then env.runScript(driver,"OnUpdate",.05) end end
    check("world ants advance toward endpoint with time",visible(canvas)[1].point[4]>oldX)
    facing=math.pi*1.5;p.Navigation.Refresh()
    check("facing changes instruction without a quest event",summary.status:GetText():find("Continue ahead",1,true))
    position={mapID=1426,x=.47,y=.5};route.meters=40;route.points[1]=position
    p.Navigation.Refresh()
    check("distance updates as player approaches",summary.status:GetText():find("40 yd",1,true))
    rotates=true;p.Navigation.Refresh();mini=visible(Minimap)
    check("rotating minimap puts east ahead when facing east",#mini>0 and math.abs(mini[1].point[4]-100)<.001 and mini[1].point[5]>-100)
    p.Command("arrow off");env.flushTimers();p.Navigation.Refresh()
    check("map ants independent of optional arrow",not arrow:IsShown() and #visible(canvas)>0 and #visible(Minimap)>0)
    p.Command("arrow on");env.flushTimers()
    radius=50;p.Navigation.Refresh()
    check("zoomed route ants remain clipped",#visible(Minimap)>0)
    C_Minimap.GetViewRadius=nil;p.Navigation.Refresh()
    check("unknown minimap scale hides ants without guessing",#visible(Minimap)==0 and #visible(canvas)>0)
    position=route.next;route.meters=0;p.Navigation.Refresh()
    check("route end requests checking quest, never claims completion",summary.status:GetText()=="Route ends nearby\nCheck the quest target")
    route=nil;p.Navigation.Refresh()
    check("invalidated path clears both ant pools",#visible(canvas)==0 and #visible(Minimap)==0)
    check("missing walking route identifies marker and live distance",arrow.label:GetText()=="Marker E · 20 yd\nNo walking route")
    p.Terrain.Status=function() return {status="loading"} end
    p.Navigation.Refresh()
    check("loading fallback gives marker direction without pretending to walk",arrow.label:GetText()=="Marker E · 20 yd\nRoute loading")
    position={mapID=1426,x=.48,y=.5};p.Navigation.Refresh()
    check("marker-only distance updates with movement",arrow.label:GetText():find("40 yd",1,true))
    CreateFrame,Minimap,C_Minimap,GetCVarBool,GetPlayerFacing,p.Terrain,p.Context.Position=unpack(old,1,7)
    p.View.Window:Hide()
end
