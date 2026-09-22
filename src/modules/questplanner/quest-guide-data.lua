-- Definitions reviewed against an exact Forever observation, not a universal quest corpus.
local identity={product="forever",build="1.60.1.69913",locale="enUS"}
assert(RikUI.QuestPlanner.StepBindings.Install({
    identity=identity,revision="dun-morogh-observed-objectives-v1",
    source={product="forever",build=identity.build,locale=identity.locale,id="dun-morogh-native-objectives",authority="verified"},
    observationSHA256="042db64be2fffd28595a36e9d727962f77a81b0aa18f926f455ec091e8ebdf4c",
    quests={
        {questID=310,title="Bitter Rivals",objectives={
            {id="q310.barrel-replacement",type="log",required=1,text="In the basement of the Thunderbrew Distillery in Kharanos, replace a barrel of Thunder Ale with a Barrel of Barleybrew Scalder."}}},
        {questID=313,title="The Grizzled Den",objectives={
            {id="q313.wendigo-manes",type="item",required=8,text="#/# Wendigo Mane"}}},
        {questID=287,title="Frostmane Hold",objectives={
            {id="q287.headhunter-kills",type="monster",required=5,text="#/# Frostmane Headhunter slain"},
            {id="q287.explore-hold",type="event",required=1,text="Fully explore Frostmane Hold"}}},
    }
}))
