-- Codec arithmetic and bounded retained state, independent of terrain path search.
return function(check)
    local old=RikUI
    local ok,err=pcall(function()
        RikUI={}
        RikUI["Secret"]={IsSecret=function() return false end}
        dofile("src/modules/questplanner/quest-schema.lua")
        dofile("src/modules/questplanner/quest-path-codec.lua")
        local codec=RikUI.QuestPlanner.PathCodec
        local chunks={[[0000000000000000001h00000008hm00000008j67%fCp`ymNH0RR91000000RR910001h|NsC0|NrlQS@Zb9A8w@q$^ZYKYWTar]]}
        local reader=assert(codec.Open(chunks,80,8,10))
        local expected={0,-0,1,-1,math.pi,2^-1074,-2^-1074,1.7976931348623157e308,1e-300,-7160.4165039062}
        for index,value in ipairs(expected) do
            check("lossless finite double "..index,reader:Number(index,0)==value,tostring(reader:Number(index,0)))
        end
        check("signed zero preserved",1/reader:Number(2,0)==-math.huge)
        check("negative and past-end records rejected",reader:Number(0,0)==nil and reader:Number(11,0)==nil)
        check("record fields cannot escape stride",reader:Number(1,1)==nil and reader:UInt(1,7,2)==nil)
        check("integer width bounded",reader:UInt(1,0,5)==nil)
        local pages={string.rep("00000",6400),[[70p`*]]}
        local large=assert(codec.Open(pages,25604,4,6401))
        check("random access crosses encoded page boundary",large:UInt(6400,0,4)==0 and large:UInt(6401,0,4)==123456789)
        for _=1,1000 do large:UInt(6401,0,4) end
        check("decoded cache stays at one word",large:Stats().retainedGroups==1 and large:Stats().decodedGroups==2)
        check("short nonfinal page rejected",not codec.Open({"00000","00000"},8,4,2))
        check("truncated and oversized layout rejected",not codec.Open({"0000"},4,4,1) and not codec.Open({},67108865,1,67108865))
        local invalid=assert(codec.Open({"~~~~~"},4,4,1))
        check("overflowing base85 word rejected",invalid:UInt(1,0,4)==nil)
        invalid=assert(codec.Open({"     "},4,4,1))
        check("invalid alphabet rejected",invalid:UInt(1,0,4)==nil)
        local empty=assert(codec.Open({},0,1,0))
        check("empty stream never permits a record read",empty:UInt(1,0,1)==nil)
    end)
    RikUI=old
    check("path stream codec fixture completes",ok,err)
end
