// Drive the public guided workflow before interacting with a control.
import {expect} from "@playwright/test";
export async function studioControl(page,id){
 const choose=new Set(["import-code","import","creator-update","pack-picker"]);
 const style=new Set(["theme","accessibility"]);
 const layout=new Set(["frame-group","reset-frame","align-center"]);
 const review=new Set(["export","share","theme-export","result-code","copy-code","download-code","pack-title","pack-creator","pack-revision","maintain-identity","metadata-apply","fit-conflicts"]);
 const parts=id.startsWith("part-")||id==="recipe"||id==="questtogether";
 let step=choose.has(id)?"choose":review.has(id)?"review":style.has(id)||layout.has(id)||parts?"customize":undefined;
 const target=page.locator("#"+id);
 if(step && !(await target.isVisible())){
  await page.locator('.studio-steps [data-step="'+step+'"]').click();
  if(step==="customize")await page.locator("#tab-"+(style.has(id)?"style":layout.has(id)?"layout":"parts")).click();
 }
 if(choose.has(id)&&id!=="pack-picker"){
  if(!await page.locator("#import-section").evaluate(el=>el.open))await page.locator("#import-section>summary").click();
  if(id==="creator-update"&&!await target.isVisible())await page.getByText("Update this creator pack",{exact:true}).click();
 }
 if(id==="theme-export"&&!await target.isVisible())await page.getByText("Share only the theme",{exact:true}).click();
 if(id==="questtogether"&&!await target.isVisible())await page.getByText("Specialist addon compatibility",{exact:true}).click();
 await expect(target).toBeVisible();
}
