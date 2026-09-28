-- Base64 text holding a raw Deflate stream, opened as bytes. The client's own decoder is used when
-- it returns the expected length; otherwise the stream is read here in Lua, in slices when the
-- caller runs in a coroutine. Nothing is trusted: a short, long or malformed stream is refused.
local planner=RikUI.QuestPlanner
local schema,inflate=planner.Schema,{}
planner.Inflate=inflate
local MAX_BYTES,MAX_TEXT=4194304,4194304
local SLICE=4096            -- output bytes between yields
local ALPHABET="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local digits={}
for index=1,#ALPHABET do digits[ALPHABET:byte(index)]=index-1 end
local PAD=("="):byte()
local LENGTH_BASE={3,4,5,6,7,8,9,10,11,13,15,17,19,23,27,31,35,43,51,59,67,83,99,115,131,163,195,227,258}
local LENGTH_EXTRA={0,0,0,0,0,0,0,0,1,1,1,1,2,2,2,2,3,3,3,3,4,4,4,4,5,5,5,5,0}
local DISTANCE_BASE={1,2,3,4,5,7,9,13,17,25,33,49,65,97,129,193,257,385,513,769,1025,1537,2049,3073,4097,6145,
    8193,12289,16385,24577}
local DISTANCE_EXTRA={0,0,0,0,1,1,2,2,3,3,4,4,5,5,6,6,7,7,8,8,9,9,10,10,11,11,12,12,13,13}
local CODE_ORDER={16,17,18,0,8,7,9,6,10,5,11,4,12,3,13,2,14,1,15}
local POWER={}
for bits=0,32 do POWER[bits]=2^bits end

local function pause()
    local thread,main=coroutine.running()
    if thread and not main then coroutine.yield() end
end

-- How many bytes the text holds, or nil when it is not whole base64.
local function decodedLength(text)
    local size=#text
    if size==0 or size%4~=0 or size>MAX_TEXT then return nil end
    local pad=0
    if text:byte(size)==PAD then pad=1 end
    if pad==1 and text:byte(size-1)==PAD then pad=2 end
    return size/4*3-pad
end

-- Bytes of the base64 text, three at a time, without building the decoded string.
local function source(text)
    local length=decodedLength(text)
    if not length then return nil end
    local group,first,second,third=-1,0,0,0
    return function(position)
        if position>=length then return nil end
        local wanted=math.floor(position/3)
        if wanted~=group then
            local at=wanted*4
            local a,b=digits[text:byte(at+1)],digits[text:byte(at+2)]
            local charC,charD=text:byte(at+3),text:byte(at+4)
            local c,d=digits[charC],digits[charD]
            -- Padding stands only where decodedLength counted it, at the very end.
            if not a or not b or not c and charC~=PAD or not d and charD~=PAD then return nil end
            c,d=c or 0,d or 0
            local word=((a*64+b)*64+c)*64+d
            group,first,second,third=wanted,math.floor(word/65536),math.floor(word/256)%256,word%256
        end
        local slot=position%3
        return slot==0 and first or slot==1 and second or third
    end,length
end

-- Canonical Huffman table from code lengths (symbols count from 0).
local function huffman(lengths,size)
    local count,symbols,offsets={}, {}, {}
    for bits=0,15 do count[bits]=0 end
    for symbol=0,size-1 do count[lengths[symbol] or 0]=count[lengths[symbol] or 0]+1 end
    local left=1
    for bits=1,15 do
        left=left*2-count[bits]
        if left<0 then return nil end
    end
    offsets[1]=0
    for bits=1,14 do offsets[bits+1]=offsets[bits]+count[bits] end
    for symbol=0,size-1 do
        local bits=lengths[symbol] or 0
        if bits~=0 then symbols[offsets[bits]]=symbol;offsets[bits]=offsets[bits]+1 end
    end
    return {count=count,symbols=symbols,complete=left==0}
end

local fixedLiterals,fixedDistances
local function fixed()
    if not fixedLiterals then
        local lengths={}
        for symbol=0,143 do lengths[symbol]=8 end
        for symbol=144,255 do lengths[symbol]=9 end
        for symbol=256,279 do lengths[symbol]=7 end
        for symbol=280,287 do lengths[symbol]=8 end
        fixedLiterals=huffman(lengths,288)
        lengths={}
        for symbol=0,29 do lengths[symbol]=5 end
        fixedDistances=huffman(lengths,30)
    end
    return fixedLiterals,fixedDistances
end

-- Reads the whole stream into a byte array of exactly `bytes` entries.
local function read(byteAt,bytes)
    local out,size,position,hold,held={},0,0,0,0
    local function take(wanted)
        while held<wanted do
            local byte=byteAt(position)
            if not byte then return nil end
            hold=hold+byte*POWER[held];held=held+8;position=position+1
        end
        local value=hold%POWER[wanted]
        hold=(hold-value)/POWER[wanted];held=held-wanted
        return value
    end
    local function symbol(table)
        local code,first,index=0,0,0
        for bits=1,15 do
            local bit=take(1)
            if not bit then return nil end
            code=code+bit
            local count=table.count[bits]
            if code-count<first then return table.symbols[index+code-first] end
            index=index+count;first=(first+count)*2;code=code*2
        end
        return nil
    end
    local function blocks(literals,distances)
        while true do
            local value=symbol(literals)
            if not value then return nil,"Invalid packed symbol" end
            if value<256 then
                if size>=bytes then return nil,"Packed data is longer than declared" end
                size=size+1;out[size]=value
                if size%SLICE==0 then pause() end
            elseif value==256 then
                return true
            else
                value=value-256
                if value>29 then return nil,"Invalid packed length" end
                local extra=take(LENGTH_EXTRA[value])
                local code=symbol(distances)
                if not extra or not code or code>29 then return nil,"Invalid packed distance" end
                local length=LENGTH_BASE[value]+extra
                local more=take(DISTANCE_EXTRA[code+1])
                if not more then return nil,"Truncated packed data" end
                local distance=DISTANCE_BASE[code+1]+more
                if distance>size then return nil,"Packed distance reaches before the start" end
                if size+length>bytes then return nil,"Packed data is longer than declared" end
                for _=1,length do
                    size=size+1;out[size]=out[size-distance]
                    if size%SLICE==0 then pause() end
                end
            end
        end
    end
    local function dynamic()
        local literalCount,distanceCount,codeCount=take(5),take(5),take(4)
        if not codeCount then return nil,"Truncated packed data" end
        literalCount,distanceCount,codeCount=literalCount+257,distanceCount+1,codeCount+4
        if literalCount>286 or distanceCount>30 then return nil,"Invalid packed table" end
        local lengths={}
        for index=1,codeCount do
            local bits=take(3)
            if not bits then return nil,"Truncated packed data" end
            lengths[CODE_ORDER[index]]=bits
        end
        local codes=huffman(lengths,19)
        if not codes or not codes.complete then return nil,"Invalid packed table" end
        lengths={}
        local index=0
        while index<literalCount+distanceCount do
            local value=symbol(codes)
            if not value then return nil,"Invalid packed table" end
            if value<16 then
                lengths[index]=value;index=index+1
            else
                local previous,times=0,nil
                if value==16 then
                    if index==0 then return nil,"Invalid packed table" end
                    previous=lengths[index-1];times=take(2);times=times and times+3
                elseif value==17 then times=take(3);times=times and times+3
                else times=take(7);times=times and times+11 end
                if not times or index+times>literalCount+distanceCount then return nil,"Invalid packed table" end
                for _=1,times do lengths[index]=previous;index=index+1 end
            end
        end
        if (lengths[256] or 0)==0 then return nil,"Invalid packed table" end
        local distanceLengths={}
        for at=0,distanceCount-1 do distanceLengths[at]=lengths[literalCount+at] end
        local literals,distances=huffman(lengths,literalCount),huffman(distanceLengths,distanceCount)
        if not literals or not distances then return nil,"Invalid packed table" end
        return blocks(literals,distances)
    end
    local function stored()
        hold,held=0,0
        local low,high,notLow,notHigh=byteAt(position),byteAt(position+1),byteAt(position+2),byteAt(position+3)
        if not notHigh then return nil,"Truncated packed data" end
        local length=low+high*256
        if length+notLow+notHigh*256~=65535 then return nil,"Invalid stored block" end
        position=position+4
        if size+length>bytes then return nil,"Packed data is longer than declared" end
        for _=1,length do
            local byte=byteAt(position)
            if not byte then return nil,"Truncated packed data" end
            size=size+1;out[size]=byte;position=position+1
            if size%SLICE==0 then pause() end
        end
        return true
    end
    repeat
        local last,kind=take(1),take(2)
        if not kind then return nil,"Truncated packed data" end
        local ok,reason
        if kind==0 then ok,reason=stored()
        elseif kind==1 then ok,reason=blocks(fixed())
        elseif kind==2 then ok,reason=dynamic()
        else return nil,"Invalid packed block" end
        if not ok then return nil,reason end
    until last==1
    if size~=bytes then return nil,"Packed data is shorter than declared" end
    if byteAt(position) then return nil,"Packed data has trailing bytes" end
    return out
end

-- The client's decoder, when present and when its answer has the declared length.
local function native(text,bytes)
    local util=C_EncodingUtil
    if type(util)~="table" or type(util.DecodeBase64)~="function" or type(util.DecompressString)~="function" then
        return nil
    end
    local method=type(Enum)=="table" and type(Enum.CompressionMethod)=="table" and Enum.CompressionMethod.Deflate or nil
    local ok,packed=pcall(util.DecodeBase64,text)
    if not ok or type(packed)~="string" or #packed~=decodedLength(text) then return nil end
    local done,raw=pcall(util.DecompressString,packed,method)
    if not done or type(raw)~="string" or #raw~=bytes then return nil end
    return raw
end

-- Returns a reader over exactly `bytes` bytes, or nil and a reason. Byte(index) counts from 1 and
-- checks its index; Get(index) is the same read for a caller that keeps its own bounds.
function inflate.Open(text,bytes)
    if type(text)~="string" or not schema.Integer(bytes,0,MAX_BYTES) or not decodedLength(text) then
        return nil,"Invalid packed data"
    end
    local raw,get=native(text,bytes),nil
    if raw then
        get=function(index) return raw:byte(index) end
    else
        local out,reason=read(source(text),bytes)
        if not out then return nil,reason end
        get=function(index) return out[index] end
    end
    return {bytes=bytes,native=raw~=nil,Get=get,Byte=function(_,index)
        if not schema.Integer(index,1,bytes) then return nil end
        return get(index)
    end}
end
