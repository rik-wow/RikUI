export const docsScript = `
const nav = document.querySelector(".docs-nav-toggle");
const wide = matchMedia("(min-width:781px)");
function sizeNav(){ if(nav) nav.open = wide.matches; }
sizeNav(); wide.addEventListener("change",sizeNav);
const input = document.querySelector("#docs-search");
const links = [...document.querySelectorAll("[data-doc-link]")];
input?.addEventListener("input",()=>{
 const value=input.value.trim().toLowerCase();
 let visible=0;
 links.forEach(link=>{link.hidden=!(link.textContent+" "+(link.dataset.keywords||"")).toLowerCase().includes(value);if(!link.hidden)visible++;});
 document.querySelectorAll(".nav-group").forEach(group=>{group.hidden=![...group.querySelectorAll("a")].some(link=>!link.hidden);});
 document.querySelector("#search-empty").hidden=visible!==0;
});
`;
