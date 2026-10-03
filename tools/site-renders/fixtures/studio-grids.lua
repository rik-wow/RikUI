-- A sprite sheet made solely from native secure bar subtrees.
function RikRenderStudioGrids(size,mixed)
    RikRenderScreenState()
    local keys={"main","bar2","bar3","bar4","bar5","stance","pet"}
    local holder=CreateFrame("Frame","RikRenderStudioGrids",UIParent)
    holder:SetSize(700,1400);holder:SetPoint("BOTTOMLEFT",UIParent,"BOTTOMLEFT",0,0)
    local shapes=mixed and {main={columns=4,size=42,spacing=2},bar2={columns=6,size=30,spacing=4},
        bar3={columns=12,size=36,spacing=6},bar4={columns=3,size=48,spacing=0},bar5={columns=2,size=30,spacing=8}} or {}
    for _,key in ipairs(keys) do assert(RikUI.Bars.SetLayout(key,shapes[key] or {columns=4,size=size,spacing=6})) end
    local y=8
    for _,key in ipairs(keys) do
        local bar=assert(RikUI.Bars.Frames[key] or RikUI.Bars.ControlFrames[key])
        if key=="pet" or key=="stance" then pcall(UnregisterStateDriver,bar,"visibility") end
        bar:SetParent(holder);bar:SetScale(1);bar:ClearAllPoints();bar:SetPoint("TOPLEFT",holder,"TOPLEFT",8,-y)
        bar:SetAlpha(1);bar:Show()
        local count=key=="stance" and math.max(1,bar.formCount or 1) or #bar.buttons
        local grid=RikUI.LayoutMetrics.Grid(count,RikUI.LayoutMetrics.BarOptions(key,RikUI.Profile))
        assert(math.abs(bar:GetWidth()-grid.width)<0.01 and math.abs(bar:GetHeight()-grid.height)<0.01)
        for index,button in ipairs(bar.buttons) do
            if index<=count then
                local x,dy=RikUI.LayoutMetrics.Cell(index,grid)
                local _,_,_,actualX,actualY=button:GetPoint()
                assert(actualX==x and actualY==dy,"Native grid cell disagrees")
            end
        end
        local record=holder:CreateFontString("RikRenderGridGeometry"..key,"OVERLAY","GameFontNormal")
        record:SetText(string.format("STUDIO_GROUP %s %.3f %.3f %.3f %.3f",key,8,1400-y-grid.height,grid.width,grid.height));record:Hide()
        y=y+grid.height+16
    end
    assert(y<1400,"Native grid atlas exceeds bounds")
    -- Force/query native region layout and assert resized borders before the snapshot.
    for _,key in ipairs(keys) do
        local bar=RikUI.Bars.Frames[key] or RikUI.Bars.ControlFrames[key]
        for _,button in ipairs(bar.buttons) do
            for index,edge in ipairs(button.border or {}) do
                local _,_,width,height=edge:GetRect()
                assert(math.abs(width-(index<=2 and button:GetWidth() or 1))<0.01 and math.abs(height-(index<=2 and 1 or button:GetHeight()))<0.01,"Native resized border disagrees")
            end
        end
    end
end
