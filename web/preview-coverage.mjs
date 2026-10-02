// Appearance coverage of reviewed native samples, independently for each component.
const samples={
 unitframes:{healthText:"both",powerText:"both"},castbars:{widthScale:1,height:22,timeText:true},
 bags:{columns:10,itemLevels:false,capacityHUD:true,capacityLowOnly:false,capacityThreshold:4},
 minimap:{performance:false,serverTime:false,coordinates:true,dayNight:true},
 xpbar:{compact:false,text:true,ticks:true,pace:false},
 nameplates:{threatText:true,selectedScale:1.15,otherAlpha:0.6},
 questtracker:{maxVisible:0,hideCompleted:false,readyFirst:false},
 chat:{fontSize:14,timestamps:true,locked:true,panel:true,classColors:true,shortTags:true,mentions:true,collapseRepeats:true,jumpButton:true,history:true,arrowHistory:true,stickyChannels:true,channelStrip:true,editColor:true,tabsVisible:true,nameClicks:true,mutedPhrases:"",highlightWords:""}
};
const sectionFor={player:"unitframes",target:"unitframes",focus:"unitframes",tot:"unitframes",petframe:"unitframes",party:"unitframes",raid:"unitframes",castplayer:"castbars",casttarget:"castbars",castfocus:"castbars",castpet:"castbars",bags:"bags",bagspace:"bags",minimap:"minimap",xpbar:"xpbar",nameplates:"nameplates",questtracker:"questtracker",chat:"chat"};
const nonvisual=new Set(["bags.searches","bags.protectFavorites","bags.favorites","bags.autoRepair","bags.repairGuild","bags.autoSellJunk","questtracker.autoWatch","questtracker.collapseInCombat","questtracker.collapsed","xpbar.animations","chat.locked","chat.history","chat.arrowHistory","chat.stickyChannels","chat.nameClicks"]);
function themeCovered(profile,engine,key){
 const expected=engine.call("Theme",key);
 return engine.call("Equal",profile.theme,expected.theme)&&(profile.font||"bundled")===expected.font&&
 [1,1.15].includes(profile.textScale||1)&&engine.call("Equal",profile.borderColor,expected.borderColor);
}
function sectionCovered(section,profile){
 for(const [field,value]of Object.entries(profile[section]||{})){
  if(nonvisual.has(section+"."+field))continue;
  if(section==="chat"&&field==="size"){if(value.width!==430||value.height!==136)return false;continue;}
  if(!Object.hasOwn(samples[section],field)||samples[section][field]!==value)return false;
 }return true;
}
export function componentAppearanceCovered(group,profile,engine,key){
 if(!themeCovered(profile,engine,key))return false;
 if(["main","bar2","bar3","bar4","bar5","stance","pet"].includes(group)&&
 (profile.showHotkeys===false||profile.showCooldownNumbers===false||profile.gryphons===true||profile.ghosts===false))return false;
 const section=sectionFor[group];return !section||sectionCovered(section,profile);
}
export function sampleAppearanceCovered(profile,engine,key){
 if(!themeCovered(profile,engine,key)||profile.showHotkeys===false||profile.showCooldownNumbers===false||profile.gryphons===true||profile.ghosts===false)return false;
 return Object.keys(samples).every(section=>sectionCovered(section,profile));
}
