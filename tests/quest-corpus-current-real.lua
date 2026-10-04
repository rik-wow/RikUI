-- Verify the locally compiled corpus through its actual deferred Lua loader.
-- Usage: luajit tests/quest-corpus-current-real.lua <corpus root> <verified build> <union quests>
local root,build,expected=assert(arg[1]),assert(arg[2]),assert(tonumber(arg[3]))
RikUI={};RikUI["Secret"]={IsSecret=function() return false end}
dofile("src/modules/questplanner/quest-schema.lua")
dofile("src/modules/questplanner/quest-semantic-data.lua")
local p=RikUI.QuestPlanner
local generated=dofile("tests/generated_stub.lua")
generated.Load(generated.Base(root),{"corpus"})
local catalog=assert(RikUIQuestCorpusCatalog)
local identity=catalog.identity
assert(identity.product=="forever" and identity.build==build,"Corpus is not for the verified current build")
local context={origin="live",attributes={faction="Alliance",class=1}}
local buckets={}
for bucket in pairs(catalog.partitions)do buckets[#buckets+1]=bucket end
table.sort(buckets)
for _,bucket in ipairs(buckets)do
    p.SemanticData.Ensure({identity=identity,order={bucket*catalog.partitionSize+1}},context)
    local steps=0
    while p.SemanticData.Status().queuedPartitions>0 do
        p.SemanticData.Step();steps=steps+1
        assert(steps<50000,"Partition load did not settle")
        assert(p.SemanticData.Status().state~="unavailable",p.SemanticData.Status().reason)
    end
end
assert(p.SemanticData.Status().loadedPartitions==#buckets,"Generated partitions missing")
local union,personas,unknown={},0,0
for _,faction in ipairs({"Alliance","Horde"})do
    for _,class in ipairs({1,2,3,4,5,7,8,9,11})do
        context.attributes={faction=faction,class=class}
        p.SemanticData.Ensure({identity=identity,order={}},context)
        personas=personas+1
        for _,bucket in ipairs(buckets)do
            for id=math.max(1,bucket*catalog.partitionSize),(bucket+1)*catalog.partitionSize-1 do
                local quest=p.SemanticData.Quest(identity,id)
                if quest then
                    assert(quest.id==id and type(quest.title)=="string","Invalid materialized quest")
                    if not union[id]then
                        union[id]=true
                        if not quest.objectives or #quest.objectives==0 then unknown=unknown+1 end
                    end
                end
            end
        end
    end
end
local count=0;for _ in pairs(union)do count=count+1 end
assert(count==expected,"Available current union did not load: "..count.." expected "..expected)
local mismatched={product=identity.product,build=build.."-fixture-mismatch",locale=identity.locale}
p.SemanticData.Ensure({identity=mismatched,order={}},context)
assert(p.SemanticData.Status().state=="identity-mismatch","Mismatched build admitted")
local first=next(union)
assert(not p.SemanticData.Quest(mismatched,first),"Stale corpus exposed for another identity")
io.write(string.format("CURRENT_CORPUS_OK build=%s quests=%d personas=%d partitions=%d emptyObjectiveRecords=%d\n",
    build,count,personas,#buckets,unknown))
