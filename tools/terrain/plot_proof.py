"""Render offline geometry evidence; never controls the game or desktop."""
import argparse,json,pathlib
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.collections import PolyCollection
from matplotlib.patches import Rectangle
import numpy as np
p=argparse.ArgumentParser();p.add_argument('--geometry',default='geometry-full.json');p.add_argument('--nav',default='full-tile-m2');p.add_argument('--out',default='full-tile-proof.png');a=p.parse_args()
g=json.loads(pathlib.Path(a.geometry).read_text());folder=pathlib.Path(a.nav);n=json.loads((folder/'manifest.json').read_text())
r=json.loads(pathlib.Path(g['source']['acquisitionReceipt']['path']).read_text())['mappingEvidence']['UiMapAssignment'][0]
xmin,xmax=float(r['Region_0']),float(r['Region_3']);ymin,ymax=float(r['Region_1']),float(r['Region_4'])
def to_map(point):return [(ymax-point[0])/(ymax-ymin)*100,(xmax-point[2])/(xmax-xmin)*100]
v=np.array(g['positions']).reshape(-1,3);tri=np.array(g['indices']).reshape(-1,3)
xy=np.array([to_map(p) for p in v]);height=v[:,1]
fig,axes=plt.subplots(1,2,figsize=(14,7.8),layout='constrained')
for ax in axes:
 ax.tripcolor(xy[:,0],xy[:,1],tri,height,shading='gouraud',cmap='Greys',rasterized=True)
 ax.set_aspect((xmax-xmin)/(ymax-ymin));ax.set_xlim(xy[:,0].min()-.15,xy[:,0].max()+.15);ax.set_ylim(xy[:,1].max()+.2,xy[:,1].min()-.2);ax.set_xlabel('Dun Morogh map X (%)');ax.set_ylabel('Dun Morogh map Y (%)');ax.grid(alpha=.15)
axes[0].set_title('Exact-build terrain: 65,456 triangles\n80 triangles removed for encoded terrain holes')
polys=[]
for entry in n['regions']:
 shard=json.loads((folder/entry['filename']).read_text())
 polys.extend([[to_map(p) for p in poly['points']] for poly in shard['polygons']])
axes[1].add_collection(PolyCollection(polys,facecolors='#37a0c3',edgecolors='#0c536b',linewidths=.12,alpha=.62))
for index,box in enumerate(n.get('exclusions',[])):
 lo,hi=box['bounds'];pad=box['padding'];a0=to_map([hi[0]+pad,0,hi[2]+pad]);a1=to_map([lo[0]-pad,0,lo[2]-pad])
 axes[1].add_patch(Rectangle(a0,a1[0]-a0[0],a1[1]-a0[1],facecolor='#b72020',edgecolor='#8b1414',alpha=.45,hatch='///',label='Uncertain collision footprint excluded' if index==0 else None,zorder=5))
if n.get('exclusions'):axes[1].legend(loc='lower left',fontsize=8)
probe=n['probes'][0];route=np.array([to_map(p) for p in probe['path']])
axes[1].plot(route[:,0],route[:,1],color='#ff6500',linewidth=2.5,zorder=6)
axes[1].scatter(route[[0,-1],0],route[[0,-1],1],c=['#ff6500','#f2f2f2'],edgecolors='#662500',s=45,zorder=7)
axes[1].set_title(f"Calculated static navigation: {n['statistics']['polygons']:,} polygons\nExample path crosses {len(route)} waypoints")
fig.set_layout_engine('constrained',rect=(0,.05,1,.95))
fig.suptitle('Forever 1.60.1.69913 · local Azeroth tile 33_42 · offline data proof',fontsize=15)
fig.text(.5,.003,'Derived model, pending validation. Source bytes are exact-build; player physics, dynamic obstacles and native traversal remain unverified.',ha='center',fontsize=9)
fig.savefig(a.out,dpi=160)
print(json.dumps({'output':a.out,'uiMapID':1426,'tileMapBounds':{'minimum':xy.min(axis=0).tolist(),'maximum':xy.max(axis=0).tolist()},'mainPathEndpoints':route[[0,-1]].tolist(),'waypoints':len(route)}))
