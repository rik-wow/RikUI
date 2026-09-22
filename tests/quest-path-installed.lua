-- Standalone Lua 5.1 integration verifier. Execute through the workspace's
-- authorized runner: lua quest-path-installed.lua <packRoot> <repoRoot>.
-- The retained source fixture is Dun Morogh's audited backbone, not native
-- traversal evidence. This script never installs addons or writes files.
local packRoot,repoRoot=arg[1],arg[2]
assert(type(packRoot)=='string' and type(repoRoot)=='string','usage: <packRoot> <repoRoot>')
packRoot=packRoot:gsub('\\','/'):gsub('/+$','')
repoRoot=repoRoot:gsub('\\','/'):gsub('/+$','')
local checks=0
local function check(value,why)
    checks=checks+1
    if not value then error(why or 'assertion failed',2) end
    return value
end
local function finite(value)
    return type(value)=='number' and value==value and math.abs(value)<math.huge
end
local function clone(value)
    local out={};for key,item in pairs(value) do out[key]=item end;return out
end
local function xyz(value)
    check(type(value)=='table','missing point')
    local x,y,z=value.x or value[1],value.y or value[2],value.z or value[3]
    check(finite(x) and finite(y) and finite(z),'nonfinite point')
    return {x,y,z}
end
local function samePoint(actual,expected,label)
    actual=xyz(actual)
    for i=1,3 do check(actual[i]==expected[i],label..' coordinate '..i) end
end
local function distance(a,b)
    local dx,dy,dz=a[1]-b[1],a[2]-b[2],a[3]-b[3]
    return math.sqrt(dx*dx+dy*dy+dz*dz)
end
RikUI={};RikUI['Secret']={IsSecret=function()return false end}
for _,name in ipairs({'schema','nav-geometry','path-codec','path-graph'}) do
    dofile(repoRoot..'/src/modules/questplanner/quest-'..name..'.lua')
end
local planner=check(RikUI.QuestPlanner,'planner bootstrap failed')
check(type(planner.PathGraph)=='table','PathGraph missing')
local function loadAddon(name)
    check(name:match('^[%w_]+$'),'invalid addon name')
    local toc=assert(io.open(packRoot..'/'..name..'/'..name..'.toc','rb'))
    for line in toc:lines() do
        line=line:gsub('^%s+',''):gsub('%s+$','')
        if line~='' and line:sub(1,1)~='#' then
            check(line:match('^[%w_.%-]+%.lua$') and not line:find('..',1,true),'invalid TOC source path')
            dofile(packRoot..'/'..name..'/'..line)
        end
    end
    toc:close()
end
loadAddon('RikUIQuestPaths')
local catalog=check(RikUIQuestPathsCatalog,'catalog missing')
check(catalog.format=='rikui-path-backbone-v2','v2 surface format required')
check(catalog.payloadID=='77feaf7367d3aa2b9038838201e4b226d3b4c7a5de2e03eed924b5a33d2dcbfc','unexpected source fixture')
check(catalog.identity.product=='forever' and catalog.identity.build=='1.60.1.69913' and catalog.identity.locale=='enUS','fixture identity changed')
check(catalog.uiMapID==1426 and catalog.worldMapID==0,'fixture map changed')
for key,value in pairs({vertices=37848,gateways=5672,edges=38048,geometry=78482,midpoints=40933,treeEntries=362725,surfacePoints=155370}) do
    check(catalog.counts[key]==value,'fixture count changed: '..key)
end
loadAddon(catalog.addonName)
for _,part in ipairs(catalog.loadParts or {}) do loadAddon(part.addon) end
local payload=check(RikUIQuestPathsPayloads and RikUIQuestPathsPayloads[catalog.payloadID],'payload missing')
check(payload.format==catalog.format and payload.payloadID==catalog.payloadID,'payload identity differs')
local function array(name,index)
    local spec=catalog.arrays[name]
    check(type(spec)=='table' and type(index)=='number' and index%1==0 and index>=1 and index<=spec.count,'array bounds '..name)
    local page=payload.arrays[name][math.floor((index-1)/spec.pageSize)+1]
    return check(page,'missing array page')[(index-1)%spec.pageSize+1]
end
-- Independent base85/IEEE reference decoder; does not call production codec.
local alphabet='0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz!#$%&()*+-;<=>?@^_`{|}~'
local digits={};for i=1,#alphabet do digits[alphabet:sub(i,i)]=i-1 end
local readers={}
local function reader(name)
    if readers[name] then return readers[name] end
    local spec=check(catalog.streams[name],'stream spec missing')
    local chunks=check(payload.streams[name],'stream missing')
    check(#chunks==spec.parts and spec.chunkChars==32000,'stream chunk shape')
    local encodedLength=math.ceil(spec.bytes/4)*5
    for i=1,spec.parts do
        local expected=math.min(spec.chunkChars,encodedLength-(i-1)*spec.chunkChars)
        check(type(chunks[i])=='string' and #chunks[i]==expected,'stream chunk length')
    end
    local r={spec=spec,chunks=chunks,group=-1}
    function r:Byte(position)
        check(position>=0 and position<self.spec.bytes and position%1==0,'reference byte bounds')
        local group=math.floor(position/4)
        if group~=self.group then
            local offset=group*5
            local chunk=self.chunks[math.floor(offset/self.spec.chunkChars)+1]
            local first=offset%self.spec.chunkChars+1
            local word=0
            for i=first,first+4 do
                local digit=digits[chunk:sub(i,i)]
                check(digit~=nil,'invalid reference base85 digit')
                word=word*85+digit
            end
            check(word<=4294967295,'base85 group overflow')
            self.group,self.word=group,word
        end
        return math.floor(self.word/256^(3-position%4))%256
    end
    function r:UInt(record,offset,width)
        check(record>=1 and record<=self.spec.count and record%1==0,'reference record bounds')
        check(offset>=0 and width>=1 and width<=4 and offset+width<=self.spec.stride,'reference integer field bounds')
        local value=0;local start=(record-1)*self.spec.stride+offset
        for i=0,width-1 do value=value+self:Byte(start+i)*256^i end
        return value
    end
    function r:Number(record,offset)
        local low,high=self:UInt(record,offset,4),self:UInt(record,offset+4,4)
        local exponent=math.floor(high/1048576)%2048
        check(exponent~=2047,'nonfinite encoded coordinate')
        local fraction=(high%1048576)*4294967296+low
        local value
        if exponent==0 then value=(fraction/4503599627370496)*2^-1022
        else value=(1+fraction/4503599627370496)*2^(exponent-1023) end
        if high>=2147483648 then value=-value end
        return value
    end
    readers[name]=r;return r
end
local function point(r,index)
    return {r:Number(index,0),r:Number(index,8),r:Number(index,16)}
end
local started=os.clock()
local admission,why=planner.PathGraph.Begin(catalog,payload)
check(admission~=nil,'admission rejected: '..tostring(why))
local graph,admissionSteps
local admissionCap=8*(catalog.counts.edges+catalog.counts.gateways+catalog.counts.geometry+catalog.counts.treeEntries)+4096
for step=1,admissionCap do
    local result,problem,done=admission:Step(({1,17,64})[(step-1)%3+1])
    if done then check(result~=nil,'admission failed: '..tostring(problem));graph=result;admissionSteps=step;break end
    check(result==nil and problem==nil,'admission returned a partial graph')
end
check(graph~=nil,'admission exceeded bounded steps')
local stats=graph:Stats();local rawBytes=0
for name,spec in pairs(catalog.streams) do rawBytes=rawBytes+spec.bytes;reader(name) end
check(stats.gateways==catalog.counts.gateways and stats.edges==catalog.counts.edges,'graph stats count mismatch')
check(stats.encodedRawBytes==rawBytes,'graph stats byte mismatch')
local returnedCatalog=graph:Catalog();returnedCatalog.identity.product='changed-for-clone-test'
check(graph:Catalog().identity.product=='forever','Catalog exposed mutable state')
local vids,geometry,centers,mids,treeEdges,edgeIds=reader('vids'),reader('geometry'),reader('centers'),reader('mids'),reader('treeEdges'),reader('edgeIds')
local surfaceOffsets,surfacePoints,portalEnds=reader('surfaceOffsets'),reader('surfacePoints'),reader('portalEnds')
local vertexOriginal,vertexCenters,midpointCenters={},{},{}
for vertex=1,catalog.counts.vertices do
    vertexOriginal[vertex]=vids:UInt(vertex,0,3)
    vertexCenters[vertex]=point(centers,vertex)
end
for index=1,catalog.counts.midpoints do midpointCenters[index]=point(mids,index) end
local polygonsChecked=0
check(surfaceOffsets:UInt(1,0,4)==0,'surface CSR starts nonzero')
for vertex=1,catalog.counts.vertices do
    local first,last=surfaceOffsets:UInt(vertex,0,4),surfaceOffsets:UInt(vertex+1,0,4)
    check(last>=first+3 and last<=first+6 and last<=catalog.counts.surfacePoints,'surface ring offset bounds')
    local polygon,problem=graph:Polygon(vertexOriginal[vertex])
    check(polygon~=nil,'Polygon rejected: '..tostring(problem))
    check(polygon.id==vertexOriginal[vertex] and type(polygon.points)=='table' and #polygon.points==last-first,'Polygon identity/ring length')
    samePoint(polygon.center,vertexCenters[vertex],'polygon center')
    for offset=1,last-first do samePoint(polygon.points[offset],point(surfacePoints,first+offset),'polygon surface point') end
    polygonsChecked=polygonsChecked+1
end
check(surfaceOffsets:UInt(catalog.counts.vertices+1,0,4)==catalog.counts.surfacePoints,'surface CSR final offset')
local changedPolygon=graph:Polygon(vertexOriginal[1])
if changedPolygon.points[1].x~=nil then changedPolygon.points[1].x=123456789 else changedPolygon.points[1][1]=123456789 end
samePoint(graph:Polygon(vertexOriginal[1]).points[1],point(surfacePoints,1),'Polygon clone')
for gateway=1,catalog.counts.gateways do
    local vertex=array('boundary',gateway);local original=vertexOriginal[vertex]
    check(graph:Gateway(original)==gateway and graph:Original(gateway)==original,'gateway roundtrip mismatch')
    samePoint(graph:Center(gateway),vertexCenters[vertex],'gateway center')
end
local changedCenter=graph:Center(1)
if changedCenter.x~=nil then changedCenter.x=123456789 else changedCenter[1]=123456789 end
samePoint(graph:Center(1),vertexCenters[array('boundary',1)],'Center clone')
local fromVertex,toVertex,geometryCost={},{},{}
for edge=1,catalog.counts.geometry do
    local source,target,mid=geometry:UInt(edge,0,2),geometry:UInt(edge,2,2),geometry:UInt(edge,4,2)
    check(vertexOriginal[source] and vertexOriginal[target] and midpointCenters[mid],'geometry reference range')
    local segment,problem=graph:Segment(edge)
    check(segment~=nil,'Segment rejected '..edge..': '..tostring(problem))
    check(segment.from==vertexOriginal[source] and segment.to==vertexOriginal[target],'Segment directed endpoints')
    samePoint(segment.origin,vertexCenters[source],'segment origin')
    samePoint(segment.destination,vertexCenters[target],'segment destination')
    samePoint(segment.midpoint,midpointCenters[mid],'segment midpoint')
    samePoint(segment.left,point(portalEnds,edge),'segment directed left')
    samePoint(segment.right,{portalEnds:Number(edge,24),portalEnds:Number(edge,32),portalEnds:Number(edge,40)},'segment directed right')
    fromVertex[edge],toVertex[edge]=source,target
    geometryCost[edge]=distance(vertexCenters[source],midpointCenters[mid])+distance(midpointCenters[mid],vertexCenters[target])
end
-- Independent literals copied from the SHA-pinned JSON, including signed,
-- fractional and large coordinates. Dense/original edge mappings are checked.
local sourceSamples={{1,249,4195335,4195488,{-2995.333166666667,245.09640000000002,-7098.749833333334},{-2996.4165,245.02973333333333,-7099.333166666667},{-2995.5415,244.7964,-7098.0415},{-2996.1665,245.6964,-7099.6665},{-2994.9165,243.8964,-7096.4165}},{1669,21294,4428839,4428846,{-3060.833166666667,245.76306666666667,-6936.583166666667},{-3075.3748333333333,248.81306666666669,-6936.583166666667},{-3060.7915,245.2964,-6931.0415},{-3062.6665,245.8964,-6949.4165},{-3058.9165,244.6964,-6912.6665}},{1707,21425,4429856,4429857,{-3054.3165,244.9964,-6934.9665},{-3056.5415,245.4214,-6936.4165},{-3056.5415,245.1964,-6927.1665},{-3054.1665,245.6964,-6941.6665},{-3058.9165,244.6964,-6912.6665}},{1734,21456,4431879,4431878,{-2901.6665,242.3214,-6936.229},{-2901.1665,242.22140000000002,-6936.9165},{-2901.4165,242.2464,-6936.6665},{-2899.4165,242.7964,-6921.6665},{-2903.4165,241.6964,-6951.6665}},{2039,22509,4440087,4440097,{-2388.7498333333333,240.5964,-6911.499833333334},{-2386.958166666667,240.87973333333332,-6909.249833333334},{-2390.4165,240.8964,-6910.1665},{-2396.4165,241.4964,-6907.6665},{-2384.4165,240.2964,-6912.6665}},{2153,22795,4441202,4441173,{-2296.9998333333333,241.76306666666665,-6915.333166666667},{-2295.6665,241.6214,-6930.479},{-2295.4165,241.44639999999998,-6912.7915},{-2290.9165,240.7964,-6904.4165},{-2299.9165,242.0964,-6921.1665}},{4360,33528,4528238,4529159,{-1715.6665,244.3714,-6886.5415},{-1713.7915,242.8464,-6891.5415},{-1714.9165,243.4964,-6891.1665},{-1714.9165,245.8964,-6877.9165},{-1714.9165,241.0964,-6904.4165}},{5747,46845,4665398,4665406,{-2915.333166666667,245.6964,-6748.9165},{-2913.6665,244.56306666666669,-6751.9165},{-2914.4165,245.09640000000002,-6750.5415},{-2916.4165,246.4964,-6745.9165},{-2912.4165,243.6964,-6755.1665}},{6282,50054,4681815,4681817,{-1866.9165,250.62973333333332,-6718.499833333334},{-1867.6665,249.4964,-6717.5415},{-1866.9165,250.1464,-6717.5415},{-1867.4165,251.2964,-6720.9165},{-1866.4165,248.9964,-6714.1665}},{7055,55876,4753625,4753642,{-2268.9998333333333,262.6630666666667,-6658.2915},{-2265.0415,263.0964333333333,-6657.083166666667},{-2266.6665,263.14639999999997,-6658.4165},{-2266.9165,261.9964,-6654.1665},{-2266.4165,264.2964,-6662.6665}},{9775,74674,4912186,4913193,{-2100.3165,311.1164,-6564.066500000001},{-2098.729,311.5964,-6564.479},{-2098.9165,311.4964,-6564.4165},{-2098.9165,311.5964,-6564.1665},{-2098.9165,311.3964,-6564.6665}},{9792,75379,4915218,4915281,{-1934.7665000000002,246.9164,-6564.116500000001},{-1910.5665000000001,247.01639999999998,-6565.7165},{-1912.2915,246.2964,-6560.5415},{-1908.4165,247.8964,-6546.1665},{-1916.1665,244.6964,-6574.9165}},{10666,90725,5033268,5033191,{486.3335,387.071425,-6465.7915},{488.6668333333334,386.82976666666667,-6464.583166666667},{486.9585,387.09645,-6466.2915},{491.3335,386.2964,-6460.6665},{482.5835,387.8965,-6471.9165}},{10744,91288,5036111,5036109,{672.1834999999999,387.47646,-6502.5165},{671.7085,387.82981666666666,-6504.874833333334},{671.5835,387.59645,-6503.0415},{673.5835,387.3965,-6504.1665},{669.5835,387.7964,-6501.9165}},{12053,103633,5132299,5132300,{-2976.833166666667,397.46313333333336,-6386.499833333334},{-2975.583166666667,397.1631333333333,-6387.749833333334},{-2969.6665,397.49645,-6388.1665},{-2950.1665,397.7964,-6391.1665},{-2989.1665,397.1965,-6385.1665}},{12638,105669,5146738,5146715,{-2081.4165,243.5964,-6353.333166666667},{-2079.729,243.5964,-6353.729},{-2080.7915,243.5964,-6352.7915},{-2079.6665,243.5964,-6351.1665},{-2081.9165,243.5964,-6354.4165}},{12701,106772,5153805,5153792,{-1638.4998333333333,379.8298,-6390.1665},{-1639.8331666666666,379.92983333333336,-6389.749833333334},{-1635.5415,380.4465,-6389.0415},{-1645.9165,378.8965,-6391.1665},{-1625.1665,381.9965,-6386.9165}},{13078,108979,5173262,5173263,{-423.2498333333333,155.92973333333333,-6356.083166666667},{-421.9165,155.86306666666667,-6356.083166666667},{-425.6665,156.0464,-6365.1665},{-416.4165,155.5964,-6337.9165},{-434.9165,156.4964,-6392.4165}},{14348,116001,5237891,5237905,{-1320.6665,374.77975,-6276.2915},{-1314.0831666666666,372.2298,-6279.749833333334},{-1314.6665,373.49645,-6276.0415},{-1314.6665,376.6965,-6264.9165},{-1314.6665,370.2964,-6287.1665}},{14876,119700,5268495,5268486,{649.396,386.09645,-6289.479},{649.396,386.09645,-6290.7915},{649.5835,386.14639999999997,-6290.1665},{651.3335,386.4964,-6290.1665},{647.8335,385.7964,-6290.1665}},{16408,130287,5343293,5343294,{337.1835,383.37646,-6235.4665},{333.5835,385.7964666666667,-6223.749833333334},{333.8335,382.99645,-6235.4165},{333.0835,382.0964,-6257.9165},{334.5835,383.8965,-6212.9165}},{20895,169076,5594195,5594196,{1254.896,170.44639999999998,-6069.2915},{1256.9585,171.4214,-6071.354},{1246.9585,169.44639999999998,-6071.0415},{1264.8335,172.4964,-6069.6665},{1229.0835,166.3964,-6072.4165}},{22287,182985,5685250,5685252,{-2871.854,365.8965,-5882.979},{-2869.9998333333333,365.96316666666667,-5884.333166666667},{-2871.5415,365.8465,-5883.7915},{-2866.9165,365.8965,-5883.4165},{-2876.1665,365.7965,-5884.1665}},{28504,213662,5870632,5870635,{-1199.8331666666666,377.7631166666667,-5782.249833333334},{-1198.3331666666666,378.76313333333337,-5779.999833333334},{-1198.4165,378.5965,-5780.2915},{-1200.4165,378.9965,-5779.4165},{-1196.4165,378.1965,-5781.1665}},{29336,216628,5887020,5887021,{-141.24983333333333,354.6298,-5795.083166666667},{-141.08316666666667,354.6964666666667,-5796.1665},{-140.6665,354.69645,-5794.7915},{-139.1665,354.7965,-5792.4165},{-142.1665,354.5964,-5797.1665}},{29949,223393,5929036,5928973,{-2433.229,465.8464,-5706.354},{-2432.6665,465.92145000000005,-5705.729},{-2432.9165,465.8964,-5706.0415},{-2441.6665,465.8964,-5704.1665},{-2424.1665,465.8964,-5707.9165}},{32842,239211,6019091,6019095,{-1772.5415,401.62142500000004,-5648.979},{-1775.3331666666666,402.6631333333333,-5634.4165},{-1774.4165,402.39645,-5634.7915},{-1778.9165,403.1965,-5633.6665},{-1769.9165,401.5964,-5635.9165}},{33643,241864,6027325,6027340,{-1226.7498333333333,395.5964666666667,-5626.6665},{-1222.604,395.97145,-5625.729},{-1227.5415,395.44645,-5625.6665},{-1232.1665,393.4964,-5624.4165},{-1222.9165,397.3965,-5626.9165}},{33888,242300,6030348,6030347,{-1056.0831666666666,397.54645,-5664.624833333334},{-1053.9998333333333,397.99646666666666,-5663.6665},{-1054.1665,397.89645,-5664.2915},{-1055.1665,397.6965,-5662.6665},{-1053.1665,398.0964,-5665.9165}},{34209,243217,6033413,6033417,{-821.5831666666667,485.79645,-5629.499833333334},{-819.8331666666667,485.1631333333333,-5624.583166666667},{-819.9165,485.09645,-5624.6665},{-820.9165,484.4964,-5624.9165},{-818.9165,485.6965,-5624.4165}},{35495,248035,6055018,6055016,{461.6668333333334,386.6964666666667,-5645.499833333334},{463.3751666666667,386.96315000000004,-5644.333166666667},{461.9585,386.69645,-5644.9165},{461.0835,386.5964,-5643.9165},{462.8335,386.7965,-5645.9165}},{35991,251641,6079636,6079648,{-2874.9165,370.72973333333334,-5563.833166666667},{-2877.5665,372.4964,-5566.4665},{-2875.0415,370.94640000000004,-5564.4165},{-2874.6665,371.3964,-5566.4165},{-2875.4165,370.4964,-5562.4165}},{36491,254833,6091783,6091787,{-2146.3664999999996,411.53648000000004,-5622.6165},{-2150.708166666667,411.6965,-5620.6665},{-2148.1665,411.8465,-5622.6665},{-2149.9165,411.1965,-5624.4165},{-2146.4165,412.4965,-5620.9165}},{36700,255398,6096916,6096909,{-1790.3331666666666,355.6297833333333,-5612.874833333334},{-1800.0415,355.721475,-5623.1665},{-1792.2915,355.6965,-5622.7915},{-1778.9165,355.6965,-5624.4165},{-1805.6665,355.6965,-5621.1665}},{37698,258694,6106115,6106142,{-1261.4165,393.39643333333333,-5607.583166666667},{-1265.0665000000001,395.03648000000004,-5603.5165},{-1262.5415,393.54645000000005,-5606.5415},{-1266.4165,393.5964,-5604.6665},{-1258.6665,393.4965,-5608.4165}},{39242,265854,6129706,6129709,{210.37516666666667,401.46315000000004,-5597.624833333334},{208.25016666666667,402.5631333333333,-5599.333166666667},{208.0835,402.79650000000004,-5598.9165},{209.0835,401.6965,-5600.1665},{207.0835,403.8965,-5597.6665}},{40879,274456,6174805,6174746,{-1851.9665,401.15639999999996,-5550.1665},{-1852.1665,398.9964,-5533.249833333334},{-1853.2915,399.89639999999997,-5538.4165},{-1857.9165,402.5964,-5553.9165},{-1848.6665,397.1964,-5522.9165}},{41854,280366,6196306,6196359,{-559.6665,404.2964666666667,-5530.6665},{-560.7665000000001,407.15644000000003,-5543.8665},{-560.6665,403.24645,-5522.4165},{-558.4165,406.5964,-5548.4165},{-562.9165,399.8965,-5496.4165}},{42110,281649,6200480,6279192,{-247.4165,354.1298,-5496.749833333334},{-247.354,354.596425,-5489.7915},{-246.7915,354.09645,-5496.4165},{-250.6665,353.8965,-5496.4165},{-242.9165,354.2964,-5496.4165}},{43730,290776,6251545,6251546,{-1987.9998333333333,404.42980000000006,-5486.499833333334},{-1984.0415,403.61311666666666,-5491.1665},{-1988.2915,404.19645,-5487.9165},{-1985.1665,405.8965,-5483.6665},{-1991.4165,402.4964,-5492.1665}},{45338,300010,6290459,6290458,{404.7835,391.65648,-5436.9165},{397.9168333333334,393.0631333333333,-5439.749833333334},{397.8335,392.99645,-5437.7915},{398.5835,393.0964,-5443.1665},{397.0835,392.8965,-5432.4165}},{49567,315800,6378528,6378523,{1042.2085,389.74642500000004,-5387.0415},{1044.2501666666667,389.2797666666667,-5385.083166666667},{1042.7085,390.14645,-5386.4165},{1039.8335,390.4965,-5385.6665},{1045.5835,389.7964,-5387.1665}},{51124,324870,6424638,6424621,{-910.979,394.8715,-5323.854},{-909.5415,394.99649999999997,-5324.729},{-910.0415,394.8965,-5324.2915},{-909.1665,394.9965,-5322.9165},{-910.9165,394.7965,-5325.6665}},{52259,328222,6438993,6438968,{5.2085,387.7964,-5329.6665},{0.8959999999999999,388.3214,-5329.604},{1.4585,388.14639999999997,-5329.4165},{1.5835,388.0964,-5329.9165},{1.3335,388.1964,-5328.9165}},{55750,346326,6559210,6559208,{-2330.604,400.9465,-5182.979},{-2330.104,400.9965,-5183.604},{-2330.2915,400.9965,-5183.4165},{-2329.6665,400.9965,-5182.1665},{-2330.9165,400.9965,-5184.6665}},{57854,357143,6637694,6637693,{-2348.4664999999995,401.2364,-5131.5165},{-2348.854,401.1964,-5130.479},{-2348.5415,401.14639999999997,-5130.9165},{-2349.4165,401.1964,-5130.9165},{-2347.6665,401.0964,-5130.9165}},{58398,360248,6668379,6668369,{-379.1665,392.3298333333334,-5150.6665},{-377.3165,392.5165,-5153.8665},{-378.0415,392.54650000000004,-5151.0415},{-374.9165,392.8965,-5151.1665},{-381.1665,392.1965,-5150.9165}},{59222,362438,6679624,6679582,{301.0418333333334,396.0631166666667,-5114.1665},{302.7501666666667,395.49646666666666,-5113.1665},{302.7085,395.54645,-5113.5415},{302.5835,395.3965,-5112.4165},{302.8335,395.6964,-5114.6665}},{61327,371455,6751248,6751245,{-148.37483333333333,442.3630666666667,-5108.749833333334},{-144.4165,442.62975000000006,-5109.958166666667},{-146.7915,442.7464,-5109.2915},{-146.4165,442.0964,-5106.9165},{-147.1665,443.3964,-5111.6665}},{61558,372280,6754393,6754345,{61.66683333333333,392.7964,-5095.458166666667},{58.021,395.3964,-5089.104},{59.4585,395.2964,-5088.7915},{55.5835,393.9964,-5095.6665},{63.3335,396.5964,-5081.9165}},{64388,391945,6883503,6883505,{-1734.8331666666666,503.3630666666667,-4945.4165},{-1734.8331666666666,503.3630666666667,-4944.333166666667},{-1735.5415,503.3464,-4945.1665},{-1737.6665,503.2964,-4945.9165},{-1733.4165,503.3964,-4944.4165}},{65150,394957,6912082,6912097,{15.3335,387.07644,-4955.1665},{14.271,387.746425,-4956.7915},{14.4585,387.34645,-4956.1665},{15.3335,387.6965,-4956.9165},{13.5835,386.9964,-4955.4165}},{65397,395660,6915138,6914097,{205.66683333333333,398.0631,-4946.9165},{201.41683333333333,395.84645,-4948.874833333334},{205.0835,397.54645000000005,-4947.9165},{205.0835,396.5964,-4952.6665},{205.0835,398.4965,-4943.1665}},{65707,397538,6923565,6923567,{719.7834999999999,253.19639999999998,-4922.7665},{718.2334999999999,253.19639999999998,-4925.8665},{718.5835,253.1964,-4924.5415},{720.0835,253.1964,-4925.1665},{717.0835,253.1964,-4923.9165}},{70601,423264,7117875,7117877,{-1866.6665,600.6965,-4757.0415},{-1866.6665,600.671475,-4754.7915},{-1866.6665,600.6965,-4755.9165},{-1870.4165,600.6965,-4755.9165},{-1862.9165,600.6965,-4755.9165}},{71187,431257,7196737,7196741,{-1843.7498333333333,609.6965,-4673.9165},{-1845.4165,609.6631666666666,-4673.9165},{-1844.1665,611.0464999999999,-4671.5415},{-1845.4165,607.4965,-4678.6665},{-1842.9165,614.5965,-4664.4165}},{73057,448307,7354453,7354451,{-1690.5415,506.54645000000005,-4589.1665},{-1690.6665,506.64645,-4590.6665},{-1690.6665,506.5964,-4589.9165},{-1690.1665,506.5964,-4589.9165},{-1691.1665,506.5964,-4589.9165}},{74315,461064,7504910,7504968,{-1722.1665,493.44645,-4455.2915},{-1722.229,493.29645,-4453.9165},{-1722.1665,493.39645,-4454.7915},{-1722.6665,493.6965,-4454.6665},{-1721.6665,493.0964,-4454.9165}},{74832,468814,7579698,7579701,{-1935.5831666666666,502.36313333333334,-4359.833166666667},{-1934.1665,502.89643333333333,-4359.833166666667},{-1934.5415,503.09645,-4366.6665},{-1935.6665,501.6965,-4346.1665},{-1933.4165,504.4964,-4387.1665}},{75617,475567,7650470,7571462,{-2454.6665,214.42973333333336,-4334.833166666667},{-2439.3165,217.01639999999998,-4345.0665},{-2450.0415,216.8964,-4344.4165},{-2428.4165,218.3964,-4344.4165},{-2471.6665,215.3964,-4344.4165}},{75973,480536,7700485,7622722,{721.2501666666667,62.76306666666667,-4337.7915},{719.5835,64.54645000000001,-4344.9165},{719.3335,64.9464,-4344.4165},{721.5835,63.6964,-4344.4165},{717.0835,66.1964,-4344.4165}},{76637,494693,7882824,7882822,{-2624.104,43.546400000000006,-4095.6665000000003},{-2623.854,43.6214,-4097.104},{-2623.9165,43.5964,-4096.2915},{-2620.9165,43.5964,-4095.4165},{-2626.9165,43.5964,-4097.1665}},{78291,507120,8055992,8055990,{-1665.6665,140.5964,-3961.2498333333333},{-1669.0415,140.57973333333334,-3965.958166666667},{-1667.2915,141.1464,-3961.4165},{-1662.4165,139.1964,-3962.4165},{-1672.1665,143.0964,-3960.4165}},{78482,514120,8218640,8217636,{-1330.4998333333333,76.7298,-3887.583166666667},{-1331.8165000000001,77.0164,-3887.1665000000003},{-1330.9165,76.84649999999999,-3887.5415},{-1330.9165,77.2965,-3888.6665},{-1330.9165,76.3965,-3886.4165}}}
for _,sample in ipairs(sourceSamples) do
    check(edgeIds:UInt(sample[1],0,3)==sample[2],'source original edge ID')
    local segment=graph:Segment(sample[1])
    check(segment.from==sample[3] and segment.to==sample[4],'source sample endpoints')
    samePoint(segment.origin,sample[5],'source sample origin')
    samePoint(segment.destination,sample[6],'source sample destination')
    samePoint(segment.midpoint,sample[7],'source sample midpoint')
    samePoint(segment.left,sample[8],'source sample directed left')
    samePoint(segment.right,sample[9],'source sample directed right')
end
local sourcePolygonSamples={{4195335,{{-2994.9165,243.8964,-7096.4165},{-2994.9165,245.6964,-7100.1665},{-2996.1665,245.6964,-7099.6665}}},{4258816,{{909.0835,164.6964,-7096.4165},{973.0835,164.6964,-7096.4165},{973.0835,164.6964,-7160.4165},{909.0835,164.5964,-7160.4165}}},{4448333,{{-1893.9165,264.0964,-6922.6665},{-1895.6665,265.6964,-6924.4165},{-1897.4165,266.4964,-6925.9165},{-1898.9165,263.9964,-6913.1665}}},{4516929,{{-2469.4165,247.9964,-6888.9165},{-2468.6665,248.0964,-6888.1665},{-2464.1665,248.2964,-6893.6665}}},{4519981,{{-2279.1665,243.0964,-6883.4165},{-2279.6665,243.5964,-6882.9165},{-2277.9165,244.8964,-6870.1665},{-2274.6665,245.0964,-6866.6665},{-2262.6665,244.0964,-6874.6665},{-2262.1665,243.8964,-6875.4165}}},{4747294,{{-2653.1665,246.9964,-6649.6665},{-2651.9165,247.6964,-6648.4165},{-2645.4165,247.1964,-6653.9165},{-2645.6665,246.5964,-6654.9165}}},{4759599,{{-1883.9165,244.6964,-6650.1665},{-1895.6665,244.8964,-6666.6665},{-1896.4165,245.2964,-6666.6665}}},{5036197,{{702.8335,391.9965,-6497.4165},{694.8335,389.7964,-6493.9165},{693.8335,389.4965,-6493.4165}}},{5141584,{{-2408.1665,406.1965,-6342.1665},{-2408.4165,403.7965,-6349.6665},{-2410.1665,403.6965,-6349.6665}}},{5315681,{{-1394.6665,374.6964,-6237.1665},{-1394.6665,374.1964,-6237.6665},{-1394.9165,369.3965,-6264.4165},{-1394.9165,373.7964,-6200.4165}}},{5418226,{{120.8335,423.9964,-6136.9165},{120.3335,423.7964,-6136.4165},{123.0835,424.3964,-6136.4165}}},{5721111,{{-690.9165,408.8965,-5889.9165},{-686.6665,408.7965,-5898.1665},{-686.6665,408.7965,-5898.9165}}},{5762062,{{-3020.1665,334.8965,-5874.1665},{-3020.1665,334.8965,-5875.4165},{-3020.6665,334.7965,-5875.6665},{-3025.9165,333.6965,-5877.6665},{-3027.4165,334.0964,-5876.4165},{-3028.6665,333.7965,-5874.9165}}},{5793804,{{-1049.6665,398.8965,-5874.6665},{-1049.6665,399.3965,-5872.9165},{-1047.6665,401.9965,-5869.1665},{-1045.4165,400.9965,-5879.4165},{-1046.4165,400.2965,-5879.1665}}},{6101007,{{-1579.1665,407.8965,-5624.4165},{-1563.1665,399.6965,-5616.1665},{-1562.1665,399.4965,-5615.9165}}},{6148110,{{1367.0835,201.3964,-5604.1665},{1374.8335,201.8964,-5608.1665},{1374.8335,202.4964,-5608.9165}}},{6187125,{{-1078.1665,393.6964,-5523.9165},{-1078.1665,394.2964,-5522.4165},{-1076.1665,394.5964,-5521.6665}}},{6220816,{{995.0835,419.0964,-5549.6665},{992.5835,419.3965,-5549.6665},{983.5835,414.4965,-5541.9165}}},{6313072,{{-2998.4165,329.2964,-5369.9165},{-3000.4165,329.3965,-5368.4165},{-2994.9165,328.5964,-5368.4165}}},{6373449,{{724.5835,501.2964,-5412.9165},{720.8335,502.1964,-5412.9165},{720.5835,501.5964,-5412.1665},{724.8335,498.4964,-5408.1665},{724.8335,498.8964,-5408.9165}}},{6376467,{{973.0835,388.6965,-5368.4165},{966.3335,390.8965,-5374.9165},{964.3335,391.2965,-5376.6665},{909.0835,394.6965,-5368.4165}}},{6646794,{{-1725.4165,504.7964,-5169.6665},{-1716.1665,500.0964,-5169.4165},{-1724.6665,504.6965,-5170.4165}}},{6683670,{{560.8335,396.8965,-5176.4165},{562.3335,396.0964,-5173.6665},{563.3335,396.1965,-5174.1665}}},{6748164,{{-353.6665,393.6965,-5106.1665},{-337.4165,396.8965,-5112.4165},{-370.9165,392.5964,-5112.4165}}},{6985760,{{-257.9165,390.7964,-4903.9165},{-260.4165,390.0964,-4903.9165},{-268.1665,390.3965,-4901.9165},{-249.9165,391.7964,-4899.9165}}},{7079938,{{717.0835,387.8964,-4792.4165},{700.0835,393.4964,-4837.6665},{695.8335,395.9964,-4833.4165}}},{7379994,{{140.0835,366.3965,-4589.4165},{139.0835,366.0964,-4589.4165},{135.3335,365.5964,-4589.1665},{133.5835,364.2964,-4587.1665},{139.0835,369.4964,-4573.1665},{139.8335,369.7964,-4573.1665}}},{7729188,{{-2362.1665,207.0964,-4262.6665},{-2362.1665,207.5964,-4263.6665},{-2362.6665,208.9964,-4266.4165},{-2378.6665,209.0964,-4264.4165},{-2378.6665,208.8964,-4262.6665}}},{7962708,{{-2610.9165,60.9964,-4079.9165},{-2610.9165,60.9964,-4076.1665},{-2609.1665,60.9964,-4076.4165},{-2608.6665,60.9964,-4079.9165}}},{7964716,{{-2421.9165,98.8964,-4083.6665},{-2418.9165,98.8964,-4083.6665},{-2418.9165,98.3964,-4088.4165},{-2425.1665,97.5964,-4088.4165},{-2424.9165,98.2964,-4086.1665}}},{7984217,{{-1222.6665,146.3964,-4048.9165},{-1221.4165,146.3964,-4049.1665},{-1221.4165,146.7964,-4054.4165},{-1221.9165,146.5964,-4055.9165},{-1232.4165,146.3964,-4055.4165},{-1232.1665,146.6964,-4052.1665}}},{8218640,{{-1330.9165,76.3965,-3886.4165},{-1329.6665,76.4964,-3887.6665},{-1330.9165,77.2965,-3888.6665}}}}
for _,sample in ipairs(sourcePolygonSamples) do
    local polygon=graph:Polygon(sample[1])
    check(polygon and #polygon.points==#sample[2],'source polygon sample count')
    for index,position in ipairs(sample[2]) do samePoint(polygon.points[index],position,'source polygon sample') end
end
local links,witnessEdges,maxWitnessSteps,maxAbsoluteError,maxRelativeError=0,0,0,0,0
local firstRoot,firstTarget
for root=1,catalog.counts.gateways do
    local treeByTarget={}
    local treeFirst,treeLast=array('treeOffsets',root)+1,array('treeOffsets',root+1)
    for record=treeFirst,treeLast do
        local edge=treeEdges:UInt(record,0,3)
        check(fromVertex[edge]~=nil and treeByTarget[toVertex[edge]]==nil,'tree edge bounds/duplicate target')
        treeByTarget[toVertex[edge]]=edge
    end
    local first,last=array('adjOffsets',root)+1,array('adjOffsets',root+1)
    local seen=0
    for target,cost,witness,index in graph:Edges(root) do
        seen=seen+1;links=links+1
        check(index==first+seen-1 and index<=last,'Edges CSR index/order mismatch')
        check(target==array('adjTargets',index) and cost==array('adjCosts',index) and witness==array('adjWitness',index),'Edges literal mismatch')
        if not firstRoot then firstRoot,firstTarget=root,target end
        local expected={}
        if witness>0 then expected[1]=witness
        else
            local current=array('boundary',target);local finish=array('boundary',root)
            local reverse={};local visited={}
            while current~=finish do
                check(not visited[current] and #reverse<=treeLast-treeFirst+1,'reference witness cycle')
                visited[current]=true
                local edge=check(treeByTarget[current],'reference witness missing parent')
                reverse[#reverse+1]=edge;current=fromVertex[edge]
            end
            for n=#reverse,1,-1 do expected[#expected+1]=reverse[n] end
        end
        check(#expected>0,'empty nonself witness')
        local job,problem=graph:BeginWitness(root,target)
        check(job~=nil,'witness rejected: '..tostring(problem))
        local actual,used
        local rows=math.max(1,treeLast-treeFirst+1)
        local cap=math.ceil((rows*4*math.ceil(math.log(rows+1)/math.log(2))+128)/64)+32
        for step=1,cap do
            local result,failure,done=job:Step(64)
            if done then check(result~=nil,'witness failed: '..tostring(failure));actual=result;used=step;break end
            check(result==nil and failure==nil,'witness leaked partial output')
        end
        check(actual~=nil,'witness exceeded bounded steps')
        maxWitnessSteps=math.max(maxWitnessSteps,used)
        check(#actual==#expected,'witness edge count mismatch')
        local current,total=array('boundary',root),0
        for n,edge in ipairs(actual) do
            check(edge==expected[n],'witness differs from encoded directed tree/seam')
            check(fromVertex[edge]==current,'witness directed continuity mismatch')
            current=toVertex[edge];total=total+geometryCost[edge]
        end
        check(current==array('boundary',target),'witness does not end at target')
        local error=math.abs(total-cost)
        maxAbsoluteError=math.max(maxAbsoluteError,error)
        maxRelativeError=math.max(maxRelativeError,error/math.max(1,math.abs(cost)))
        check(error<=math.max(1e-9,math.abs(cost)*1e-12),'geometric witness cost mismatch')
        witnessEdges=witnessEdges+#actual
    end
    check(seen==math.max(0,last-first+1),'Edges omitted/added adjacency')
end
check(links==38048,'not every coarse link was verified')
local cancelJob=check(planner.PathGraph.Begin(catalog,payload),'cancellation admission failed')
cancelJob:Cancel()
local cancelled,cancelReason,cancelDone=cancelJob:Step(1)
check(cancelled==nil and cancelDone and type(cancelReason)=='string' and cancelReason:lower():find('cancel',1,true),'admission cancellation failed')
local witnessCancel=check(graph:BeginWitness(firstRoot,firstTarget),'cancellation witness failed')
witnessCancel:Cancel()
local cancelledWitness,witnessReason,witnessDone=witnessCancel:Step(1)
check(cancelledWitness==nil and witnessDone and type(witnessReason)=='string' and witnessReason:lower():find('cancel',1,true),'witness cancellation failed')
local rejectionCases=0
local function reject(label,change)
    local c,p=clone(catalog),clone(payload)
    c.counts=clone(catalog.counts);c.arrays=clone(catalog.arrays);c.streams=clone(catalog.streams)
    p.arrays=clone(payload.arrays);p.streams=clone(payload.streams)
    change(c,p)
    local job,problem=planner.PathGraph.Begin(c,p)
    if not job then check(type(problem)=='string',label..' rejection reason');rejectionCases=rejectionCases+1;return end
    for step=1,admissionCap do
        local result,why,done=job:Step(64)
        if done then
            check(result==nil and type(why)=='string',label..' was admitted')
            rejectionCases=rejectionCases+1;return
        end
    end
    error(label..' rejection exceeded bounded steps')
end
local function alterArray(p,name,index,value)
    local size=catalog.arrays[name].pageSize;local page=math.floor((index-1)/size)+1
    p.arrays[name]=clone(payload.arrays[name]);p.arrays[name][page]=clone(payload.arrays[name][page])
    p.arrays[name][page][(index-1)%size+1]=value
end
reject('format',function(c)c.format='invalid' end)
reject('empty gateway count',function(c)c.counts.gateways=0 end)
reject('edge count differs',function(c)c.counts.edges=c.counts.edges+1 end)
reject('zero page size',function(c)c.arrays.boundary=clone(c.arrays.boundary);c.arrays.boundary.pageSize=0 end)
reject('stream stride differs',function(c)c.streams.centers=clone(c.streams.centers);c.streams.centers.stride=23 end)
reject('surface offset record count',function(c)c.streams.surfaceOffsets=clone(c.streams.surfaceOffsets);c.streams.surfaceOffsets.count=c.counts.vertices end)
reject('portal endpoint stride',function(c)c.streams.portalEnds=clone(c.streams.portalEnds);c.streams.portalEnds.stride=24 end)
reject('negative cost',function(c,p)alterArray(p,'adjCosts',1,-1) end)
reject('nonnumeric cost',function(c,p)alterArray(p,'adjCosts',1,'bad') end)
reject('nonfinite cost',function(c,p)alterArray(p,'adjCosts',1,0/0) end)
reject('target out of range',function(c,p)alterArray(p,'adjTargets',1,c.counts.gateways+1) end)
reject('witness out of range',function(c,p)alterArray(p,'adjWitness',1,c.counts.geometry+1) end)
reject('CSR starts nonzero',function(c,p)alterArray(p,'adjOffsets',1,1) end)
reject('tree CSR ends early',function(c,p)alterArray(p,'treeOffsets',c.arrays.treeOffsets.count,c.counts.treeEntries-1) end)
reject('truncated encoded part',function(c,p)p.streams.vids=clone(p.streams.vids);p.streams.vids[1]=p.streams.vids[1]:sub(2) end)
print(string.format('{"test":"quest-path-installed","status":"passed","source":"%s","gateways":%d,"links":%d,"geometry":%d,"sourceSamples":%d,"surfacePolygons":%d,"surfacePoints":%d,"sourcePolygonSamples":%d,"witnessEdges":%d,"admissionSteps":%d,"maxWitnessSteps64":%d,"geometricMaxAbsoluteError":%.17g,"geometricMaxRelativeError":%.17g,"rejectionCases":%d,"cancellationCases":2,"checks":%d,"hostLuaElapsedSeconds":%.6f}',catalog.payloadID,catalog.counts.gateways,links,catalog.counts.geometry,#sourceSamples,polygonsChecked,catalog.counts.surfacePoints,#sourcePolygonSamples,witnessEdges,admissionSteps,maxWitnessSteps,maxAbsoluteError,maxRelativeError,rejectionCases,checks,os.clock()-started))
