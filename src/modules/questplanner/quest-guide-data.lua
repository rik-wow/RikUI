-- Definitions reviewed against an exact Forever observation, not a universal quest corpus.
local identity={product="forever",build="1.60.1.69913",locale="enUS"}
assert(RikUI.QuestPlanner.StepBindings.Install({
    identity=identity,revision="dun-morogh-observed-objectives-v2",
    source={product="forever",build=identity.build,locale=identity.locale,id="dun-morogh-native-objectives",authority="verified"},
    observationSHA256="042db64be2fffd28595a36e9d727962f77a81b0aa18f926f455ec091e8ebdf4c",
    quests={
        {questID=310,title="Bitter Rivals",objectives={
            {id="q310.barrel-replacement",type="log",required=1,text="In the basement of the Thunderbrew Distillery in Kharanos, replace a barrel of Thunder Ale with a Barrel of Barleybrew Scalder."}}},
        {questID=313,title="The Grizzled Den",objectives={
            {id="q313.wendigo-manes",type="item",required=8,text="#/# Wendigo Mane",
                navigation={kind="hunt",radius=120,source="user-reported",
                    text="Collect Wendigo Manes",nearby="Look outside the cave first",
                    instructions="Kill Wendigos and collect their manes. Look outside the Grizzled Den first; enter only if needed.",
                    basis="Outdoor Wendigos reported by the player. Search distance is guidance policy, not a verified spawn boundary."}}}},
        {questID=287,title="Frostmane Hold",objectives={
            {id="q287.headhunter-kills",type="monster",required=5,text="#/# Frostmane Headhunter slain",
                navigation={kind="hunt",radius=40,source="objective-text",text="Kill Frostmane Headhunters",
                    basis="Kill-count objective; the map pin marks a search vicinity, not a required standing position."}},
            {id="q287.explore-hold",type="event",required=1,text="Fully explore Frostmane Hold"}}},
    }
}))
