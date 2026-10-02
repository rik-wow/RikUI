-- Exact-current client identity for corpus scenarios. Simulator defaults describe a different product.
function RikRenderCurrentPlanner()
    assert(RikRenderClient and RikRenderClient.version:match("^1%.60%.%d+$"),"Current client fixture requires verified Forever source")
    local original=GetBuildInfo
    GetBuildInfo=function()
        local _,_,date,_,a,b,c=original()
        return RikRenderClient.version,RikRenderClient.build,date,16001,a,b,c
    end
end
