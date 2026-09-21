"""Plot actual before/after mesh coverage and a production Lua movement replay."""
import argparse,json,pathlib
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.collections import PolyCollection
import numpy as np

def polygons(manifest):
    path=pathlib.Path(manifest);m=json.loads(path.read_text())
    return [p['points'] for r in m['regions'] for p in json.loads((path.parent/r['filename']).read_text())['polygons']]

def local_panel(ax,rows,start,title):
    selected=[p for p in rows if any(abs(v[0]-start[0])<15 and abs(v[2]-start[1])<15 for v in p)]
    ax.add_collection(PolyCollection([[(-v[0],-v[2]) for v in p] for p in selected],
        facecolors='#294b57',edgecolors='#779ba8',linewidths=.6))
    ax.scatter(-start[0],-start[1],s=65,color='#ffcf60',marker='x',zorder=5)
    for dx in (-1,0,1):
        for dy in (-1,0,1):
            ax.scatter(-start[0]+dx*.000499*4924.9997558593,-start[1]+dy*.000499*3283.3332519531,s=12,color='white',zorder=4)
    ax.set_xlim(-start[0]-9,-start[0]+9);ax.set_ylim(-start[1]+9,-start[1]-9)
    ax.set_title(title,fontsize=12);ax.set_aspect('equal');ax.set_facecolor('#111b28')
    ax.set_xlabel('East → (world yards)');ax.set_ylabel('South → (world yards)')

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ('coarse','fine','replay','output'):parser.add_argument('--'+name,required=True)
    args=parser.parse_args();out=pathlib.Path(args.output)
    if out.exists():raise FileExistsError(out)
    data=json.loads(pathlib.Path(args.replay).read_text())
    start=(data['coarse'][0][0],data['coarse'][0][2])
    plt.rcParams.update({'text.color':'#eaf2ff','axes.labelcolor':'#c4d5e6',
        'xtick.color':'#9bb1c5','ytick.color':'#9bb1c5','axes.edgecolor':'#60768b'})
    fig,axes=plt.subplots(1,3,figsize=(17,7),facecolor='#111b28',gridspec_kw={'width_ratios':[1,1,1.6]})
    local_panel(axes[0],polygons(args.coarse),start,'Expanded area · coarse raster\ncenter rejected; 4/9 samples covered')
    local_panel(axes[1],polygons(args.fine),start,'Expanded area · finer raster\ncenter covered; 8/9 samples covered')
    ax=axes[2];ax.set_facecolor('#111b28')
    ax.add_collection(PolyCollection([[(-p[0],-p[2]) for p in pts] for _,pts in data['polygons']],
        facecolors='#243b48',edgecolors='#49616c',linewidths=.2))
    route=-np.array(data['samples'])[:,:2];ax.plot(*route.T,color='#5df6bf',linewidth=2)
    ax.scatter(*route[0],color='#ffcf60',s=35,zorder=5)
    ax.scatter(-data['marker'][0],-data['marker'][1],color='#ff78cb',marker='*',s=90,zorder=5)
    ax.set_xlim(route[:,0].min()-25,route[:,0].max()+25);ax.set_ylim(route[:,1].max()+25,route[:,1].min()-25)
    ax.set_aspect('equal');ax.set_title('Frostmane marker · simulated movement\n35.5,46.6 → 25.95,40.57',fontsize=12)
    ax.set_xlabel('East → (world yards)');ax.set_ylabel('South → (world yards)')
    fig.suptitle('Actual Dun Morogh mesh: coverage repair and route replay',fontsize=18,y=.98)
    fig.text(.04,.075,'Gold ×: screenshot center. White dots: rounding samples. Blank areas have no admitted walking polygon.',fontsize=11)
    fig.text(.04,.035,'Same physical limits; finer sampling. Green: production Lua replay, zero reversals. Native traversal remains unverified.',fontsize=11)
    fig.subplots_adjust(left=.055,right=.985,top=.88,bottom=.16,wspace=.27)
    fig.savefig(out,dpi=150,facecolor=fig.get_facecolor());print(out)
if __name__=='__main__':main()
