// Coverage of the reviewed native component samples, not a widget implementation.
// Values follow src/core/profiles.lua and the atlas fixture's native startup profile.
const samples={
 unitframes:{healthText:"both",powerText:"both"},castbars:{widthScale:1,height:22,timeText:true},
 bags:{columns:10,itemLevels:false,capacityHUD:true,capacityLowOnly:false,capacityThreshold:4},
 minimap:{performance:false,serverTime:false,coordinates:true,dayNight:true},
 xpbar:{compact:false,text:true,ticks:true,pace:false},
 nameplates:{threatText:true,selectedScale:1.15,otherAlpha:0.6},
 questtracker:{maxVisible:0,hideCompleted:false,readyFirst:false},
};
const nonvisual=new Set(["bags.searches","bags.protectFavorites","bags.favorites","bags.autoRepair","bags.repairGuild","bags.autoSellJunk","questtracker.autoWatch","questtracker.collapseInCombat","questtracker.collapsed","xpbar.animations"]);
export function sampleAppearanceCovered(profile,engine,key){
 const expected=engine.call("Theme",key);
 if(!engine.call("Equal",profile.theme,expected.theme)||(profile.font||"bundled")!==expected.font||
 ![1,1.15].includes(profile.textScale||1)||!engine.call("Equal",profile.borderColor,expected.borderColor)||
 profile.showHotkeys===false||profile.showCooldownNumbers===false||profile.gryphons===true||profile.ghosts===false)return false;
 for(const [section,values] of Object.entries(samples))for(const [field,value] of Object.entries(profile[section]||{})){
  if(nonvisual.has(section+"."+field))continue;
  if(!Object.hasOwn(values,field)||values[field]!==value)return false;
 }
 return true;
}
