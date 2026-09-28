-- Raw Deflate in base64: the Lua reader against streams written by zlib, and the choice between
-- the client's decoder and the Lua one.
return function(check)
    local old,oldUtil,oldEnum=RikUI,C_EncodingUtil,Enum
    local ok,err=pcall(function()
        RikUI={}
        RikUI["Secret"]={IsSecret=function() return false end}
        C_EncodingUtil,Enum=nil,nil
        dofile("src/modules/questplanner/quest-schema.lua")
        dofile("src/modules/questplanner/quest-inflate.lua")
        local inflate=RikUI.QuestPlanner.Inflate
        local function text(reader)
            local parts={}
            for index=1,reader.bytes do parts[index]=string.char(reader:Byte(index)) end
            return table.concat(parts)
        end
        -- The same generator as the script that packed BIG: 3000 bytes with a changing alphabet.
        local function sample(count)
            local x,parts=1,{}
            for index=0,count-1 do
                x=(x*75+74)%65537
                parts[#parts+1]=string.char(x%23+math.floor(index/97)%5*40)
            end
            return table.concat(parts)
        end
        local all={}
        for byte=0,255 do all[#all+1]=string.char(byte) end
        local HELLO="y0jNyclXyEAnAQ=="
        local STORED="AQAB//4AAQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eHyAhIiMkJSYnKCkqKywtLi8wMTIzNDU2Nzg5Ojs8PT4/QEFCQ0RFRkdISUpLTE1OT1BRUlNUVVZXWFlaW1xdXl9gYWJjZGVmZ2hpamtsbW5vcHFyc3R1dnd4eXp7fH1+f4CBgoOEhYaHiImKi4yNjo+QkZKTlJWWl5iZmpucnZ6foKGio6SlpqeoqaqrrK2ur7CxsrO0tba3uLm6u7y9vr/AwcLDxMXGx8jJysvMzc7P0NHS09TV1tfY2drb3N3e3+Dh4uPk5ebn6Onq6+zt7u/w8fLz9PX29/j5+vv8/f7/"
        local BIG="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"
        local LONG="7cUxAQAgCACwrAgI/RNYwnN7Fier72zYtm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm3btm1/+gE="

        local reader=assert(inflate.Open(HELLO,23))
        check("a fixed-table stream reads back",text(reader)=="hello hello hello hello" and reader.native==false)
        check("a stored block reads back",text(assert(inflate.Open(STORED,256)))==table.concat(all))
        check("a dynamic-table stream reads back",text(assert(inflate.Open(BIG,3000)))==sample(3000))
        check("an empty stream is zero bytes",assert(inflate.Open("AwA=",0)).bytes==0)
        check("reads outside the data return nothing",reader:Byte(0)==nil and reader:Byte(24)==nil and reader:Byte(1.5)==nil)

        check("a stream longer than declared is refused",inflate.Open(HELLO,22)==nil)
        check("a stream shorter than declared is refused",inflate.Open(HELLO,24)==nil)
        check("a cut stream is refused",inflate.Open(HELLO:sub(1,8),23)==nil and inflate.Open(BIG:sub(1,2000),3000)==nil)
        check("text that is not base64 is refused",inflate.Open("y0jNyclXyEAnAQ=",23)==nil
            and inflate.Open("y0jN*clXyEAnAQ==",23)==nil and inflate.Open("",0)==nil and inflate.Open(nil,0)==nil)
        check("a reserved block type is refused",inflate.Open("BwA=",0)==nil)
        check("a distance before the start is refused",inflate.Open("SwRCAA==",4)==nil)
        check("a declared size over the limit is refused",inflate.Open(HELLO,4194305)==nil and inflate.Open(HELLO,-1)==nil)

        -- In a coroutine the reader gives the frame back while it works.
        local yields,result=0,nil
        local thread=coroutine.create(function() result=inflate.Open(LONG,320000) end)
        while coroutine.status(thread)~="dead" do
            assert(coroutine.resume(thread))
            if coroutine.status(thread)~="dead" then yields=yields+1 end
        end
        local same=result~=nil
        for index=1,320000,997 do
            if same and result:Byte(index)~=("abcdefgh"):byte((index-1)%8+1) then same=false end
        end
        check("a long stream is read in slices and reads back",same and yields>=39 and result:Byte(320000)==("h"):byte(),
            tostring(yields))

        -- The client's decoder is used when its answer has the declared length, and only then.
        local calls=0
        Enum={CompressionMethod={Deflate=7}}
        C_EncodingUtil={DecodeBase64=function(value) calls=calls+1;return string.rep("p",math.floor(#value/4*3)-2) end,
            DecompressString=function(_,method) return method==7 and "hello hello hello hello" or "wrong" end}
        reader=assert(inflate.Open(HELLO,23))
        check("the client's decoder supplies the bytes",reader.native==true and calls==1 and text(reader)=="hello hello hello hello"
            and reader:Byte(24)==nil)
        C_EncodingUtil.DecompressString=function(value) return value end
        reader=assert(inflate.Open(HELLO,23))
        check("a decoder that returns its input gives way to the Lua reader",reader.native==false
            and text(reader)=="hello hello hello hello")
        C_EncodingUtil.DecompressString=function() error("no such method") end
        check("a decoder that fails gives way to the Lua reader",assert(inflate.Open(HELLO,23)).native==false)
        C_EncodingUtil.DecodeBase64=function() return nil end
        check("a base64 decoder that returns nothing gives way to the Lua reader",assert(inflate.Open(HELLO,23)).native==false)
    end)
    RikUI,C_EncodingUtil,Enum=old,oldUtil,oldEnum
    check("packed data fixture completes",ok,err)
end
