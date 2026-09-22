-- Random-access lossless numeric streams. No decompression library or per-record tables.
local planner=RikUI.QuestPlanner
local schema,codec=planner.Schema,{}
planner.PathCodec=codec
local CHUNK_CHARS,MAX_BYTES,MAX_RECORDS=32000,67108864,1048576
local ALPHABET="0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz!#$%&()*+-;<=>?@^_`{|}~"
local digits={}
for index=1,#ALPHABET do digits[ALPHABET:byte(index)]=index-1 end
local function byteAt(reader,position)
    local group=math.floor(position/4)
    if reader.group~=group then
        local encoded=group*5
        local part=math.floor(encoded/CHUNK_CHARS)+1
        local offset=encoded%CHUNK_CHARS+1
        local chunk=reader.chunks[part]
        local word=0
        for index=offset,offset+4 do
            local digit=digits[chunk:byte(index)]
            if digit==nil then return nil,"Invalid path stream alphabet" end
            word=word*85+digit
        end
        if word>4294967295 then return nil,"Invalid path stream word" end
        reader.group,reader.word=group,word
        reader.decoded=reader.decoded+1
    end
    return math.floor(reader.word/256^(3-position%4))%256
end
local function unsigned(reader,position,width)
    local value,multiplier=0,1
    for index=0,width-1 do
        local byte,reason=byteAt(reader,position+index)
        if byte==nil then return nil,reason end
        value=value+byte*multiplier;multiplier=multiplier*256
    end
    return value
end
local function position(reader,index,offset,width)
    if not schema.Integer(index,1,reader.count) or not schema.Integer(offset,0,reader.stride-width) then
        return nil,"Path stream record is out of bounds"
    end
    return (index-1)*reader.stride+offset
end
local function number(reader,at)
    local lo,reason=unsigned(reader,at,4)
    if lo==nil then return nil,reason end
    local hi,problem=unsigned(reader,at+4,4)
    if hi==nil then return nil,problem end
    local exponent=math.floor(hi/1048576)%2048
    if exponent==2047 then return nil,"Non-finite path coordinate" end
    local fraction=(hi%1048576)*4294967296+lo
    local value
    if exponent==0 then value=(fraction/4503599627370496)*2^-1022
    else value=(1+fraction/4503599627370496)*2^(exponent-1023) end
    if hi>=2147483648 then value=-value end
    return value
end
function codec.Open(chunks,bytes,stride,count)
    if not schema.Integer(bytes,0,MAX_BYTES) or not schema.Integer(stride,1,64)
        or not schema.Integer(count,0,MAX_RECORDS) or bytes~=stride*count
        or not schema.List(chunks,math.ceil(MAX_BYTES/4*5/CHUNK_CHARS)) then return nil,"Invalid path stream layout" end
    local size,pages=0,{}
    for index,chunk in ipairs(chunks) do
        if type(chunk)~="string" or #chunk==0 or #chunk>CHUNK_CHARS or #chunk%5~=0
            or index<#chunks and #chunk~=CHUNK_CHARS then return nil,"Invalid path stream page" end
        size=size+#chunk;pages[index]=chunk
    end
    if size~=math.ceil(bytes/4)*5 then return nil,"Truncated path stream" end
    local reader={chunks=pages,bytes=bytes,stride=stride,count=count,decoded=0}
    return {
        UInt=function(_,index,offset,width)
            if not schema.Integer(width,1,4) then return nil,"Invalid integer width" end
            local at,reason=position(reader,index,offset,width)
            if not at then return nil,reason end
            return unsigned(reader,at,width)
        end,
        Number=function(_,index,offset)
            local at,reason=position(reader,index,offset,8)
            if not at then return nil,reason end
            return number(reader,at)
        end,
        Stats=function() return {bytes=bytes,records=count,decodedGroups=reader.decoded,retainedGroups=reader.group and 1 or 0} end,
    }
end
