import numpy as np
import stackelberg_core as sc
CAP,PHI=0.35,0.8
phi=np.full(4,PHI)
def paid(P,r,cap,phi):
    out=[]
    for m in range(len(P)):
        tot=r[:,m].sum(); sh=np.minimum(r[:,m]/(tot+1e-9),cap) if cap else r[:,m]/(tot+1e-9)
        out.append(P[m]*np.sum(phi*sh))
    return np.array(out)
def UL(alpha,P,r,cap,phi,mode):
    cost = P if mode=="nominal" else paid(P,r,cap,phi)
    return float(sum(a*np.log(max(r[:,m].sum(),1e-9))-c for m,(a,c) in enumerate(zip(alpha,cost))))
g=range(1,21)
for alpha in [(4,6),(10,15)]:
    for label,kw,cap,ph in [("paper",{},None,np.ones(4)),("V3",{"cap":CAP,"phi":phi},CAP,phi)]:
        for mode in (["nominal"] if label=="paper" else ["nominal","actual-paid"]):
            best=(-1e9,None,None)
            for p1 in g:
                for p2 in g:
                    P=np.array([p1,p2],float); r=sc.follower_equilibrium(P,**kw)
                    u=UL(alpha,P,r,cap,ph,mode)
                    if u>best[0]: best=(u,P,r)
            print(alpha,label,mode,"P*",best[1],"UL*",round(best[0],2),"resources",best[2].sum(axis=0).round(1))
