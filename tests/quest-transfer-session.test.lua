-- Long journals must not prevent acquisition of the complete current log.
return function(check)
    local previous=RikUI
    local marker={}
    RikUI={}
    RikUI["Secret"]={IsSecret=function(value) return value==marker end}
    local ok,reason=pcall(function()
        dofile("src/modules/questplanner/quest-schema.lua")
        dofile("src/modules/questplanner/quest-transfer.lua")
        local p=RikUI.QuestPlanner
        local snapshot={identity={product="forever",build="1.60.1.69913",locale="enUS"},
            observedCount=1,reportedCount=1,order={98319},coverage="log-complete",
            context={attributes={level=7,xp=1980},rewards={}},
            quests={[98319]={id=98319,title="A current quest",objectivesComplete=false}}}
        local history={scope="session-only",dropped=7,entries={}}
        for index=1,48 do
            history.entries[index]={event="GOSSIP_SHOW",sequence=index,
                first=string.rep("a",2048),second=string.rep("b",2048),third=string.rep("c",2048)}
        end
        local original,calls=p.Transfer.Encode,0
        p.Transfer.Encode=function(value) calls=calls+1;return original(value) end
        local wire,problem,report=p.Transfer.EncodeSession(snapshot,history)
        p.Transfer.Encode=original
        check("large journal exports within wire budget",wire and #wire<=131072,problem)
        check("selection work bounded to seven encodes",calls<=7 and calls>1)
        local decoded=assert(p.Transfer.Decode(wire))
        local retained=report.exportedEntries
        check("journal omissions explicit",retained>0 and retained<48 and report.omittedEntries==48-retained
            and report.availableEntries==48 and report.selection=="newest-contiguous")
        check("latest contiguous entries preserved",#decoded.journal.entries==retained
            and decoded.journal.entries[1].sequence==49-retained
            and decoded.journal.entries[retained].sequence==48)
        check("ring drops separate from export omissions",decoded.journal.dropped==7
            and decoded.journal.export.omittedEntries==48-retained)
        check("current quest snapshot and context preserved",decoded.observedCount==1 and decoded.order[1]==98319
            and decoded.quests[98319].title=="A current quest" and decoded.quests[98319].objectivesComplete==false
            and decoded.context.attributes.xp==1980 and next(decoded.context.rewards)==nil)
        check("session export does not mutate live inputs",snapshot.journal==nil and history.export==nil
            and #history.entries==48 and history.entries[1].sequence==1 and history.dropped==7)
        table.insert(decoded.journal.entries,1,p.Schema.Clone(history.entries[48-retained]))
        decoded.journal.export.exportedEntries=retained+1
        decoded.journal.export.omittedEntries=47-retained
        decoded.origin=nil
        check("one more older entry exceeds packet bound",not p.Transfer.Encode(decoded))
        local before=history.entries[1].first
        history.entries[1].first=marker
        check("omission cannot conceal secret journal data",not p.Transfer.EncodeSession(snapshot,history))
        history.entries[1].first=before
        history.entries[49]={event="extra"}
        check("journal record count bound enforced",not p.Transfer.EncodeSession(snapshot,history))
        history.entries[49]=nil
        local empty={scope="session-only",dropped=0,entries={}}
        local emptyWire,_,emptyReport=p.Transfer.EncodeSession(snapshot,empty)
        check("empty journal still exports",emptyWire and emptyReport.exportedEntries==0 and emptyReport.omittedEntries==0)
        local short={scope="session-only",dropped=2,entries={{event="initial-observation"},{event="observed-progress"}}}
        local shortWire,_,shortReport=p.Transfer.EncodeSession(snapshot,short)
        check("small journal kept in full",shortWire and shortReport.exportedEntries==2 and shortReport.omittedEntries==0)
        local repeated=assert(p.Transfer.EncodeSession(snapshot,history))
        check("bounded session selection deterministic",repeated==wire)
        local tooLarge=p.Schema.Clone(snapshot);tooLarge.extra={}
        for index=1,40 do tooLarge.extra[index]=string.rep("z",2048) end
        check("oversized current log/context never silently trimmed",not p.Transfer.EncodeSession(tooLarge,history))
        local nested=p.Schema.Clone(snapshot);nested.journal={}
        check("ambiguous embedded journal rejected",not p.Transfer.EncodeSession(nested,history))
        check("invalid journal scope rejected",not p.Transfer.EncodeSession(snapshot,{scope="world",dropped=0,entries={}}))
    end)
    RikUI=previous
    check("session transfer fixtures complete",ok,reason)
end
