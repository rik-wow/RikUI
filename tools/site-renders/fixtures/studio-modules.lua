-- Startup module flags exercise actual loaded-addon output, never a simulated widget.
function RikRenderStudioModules(sample)
    assert(RikUI:GetModuleState("unitauras")=="disabled")
    local native=RikUI.GetModuleRequirements
    RikUI.GetModuleRequirements=nil
    local portableChoices=RikUI.SetupPack.ModuleChoices()
    RikUI.GetModuleRequirements=native
    for _,choice in ipairs(portableChoices) do
        local expected=assert(native(RikUI,choice.key))
        assert(RikUI.SetupPack.Equal(choice.dependencies,expected),"Pack dependency mismatch: "..choice.key)
        assert(RikUI:GetModuleState(choice.key),"Unknown portable module: "..choice.key)
    end
    local source=assert(RikUI.SetupPack.Bundled("centered"))
    local result=assert(RikUI.SetupPack.Resolve(source,{overrides={modules={chat=false,cooldowns=false}}}))
    for _,group in ipairs(result.groups)do assert(group.key~="chat" and group.key~="cooldowns","Disabled feature reserved layout space")end
    assert(#result.disabledGroups==2)
    RikRenderStudioAtlas(sample)
end
