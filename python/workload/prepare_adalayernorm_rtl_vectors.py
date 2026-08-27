#!/usr/bin/env python3
"""Generate BF16 AdaLayerNorm-style per-row affine vectors for the PCU."""
from __future__ import annotations
import csv,importlib.util,struct,sys
from pathlib import Path
import numpy as np
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/"reports/groot_normalization/results/adalayernorm_l8_vectors"
def load_model():
  p=ROOT/"tools/explore_groot_mixed_precision.py";s=importlib.util.spec_from_file_location("mixed_model",p);m=importlib.util.module_from_spec(s);sys.modules[s.name]=m;s.loader.exec_module(m);return m
def bits(v):return struct.unpack(">I",struct.pack(">f",float(v)))[0]
def write(p,v):p.write_text("\n".join(f"{int(x):04x}"for x in v)+"\n",encoding="ascii")
def add(a,b):return np.asarray(a+b,dtype=np.float32)
def reduce(x):
  rows,h=x.shape;layout=x.reshape(rows,h//128,16,8);slots=np.zeros((rows,16,4),np.float32);qs=np.zeros_like(slots)
  for i in range(layout.shape[1]):
    a=layout[:,i];q=np.asarray(a*a,dtype=np.float32)
    while a.shape[-1]>1:a=add(a[...,0::2],a[...,1::2]);q=add(q[...,0::2],q[...,1::2])
    slots[:,:,i%4]=add(slots[:,:,i%4],a[...,0]);qs[:,:,i%4]=add(qs[:,:,i%4],q[...,0])
  a=add(add(slots[:,:,0],slots[:,:,1]),add(slots[:,:,2],slots[:,:,3]));q=add(add(qs[:,:,0],qs[:,:,1]),add(qs[:,:,2],qs[:,:,3]))
  while a.shape[1]>1:a=add(a[:,0::2],a[:,1::2]);q=add(q[:,0::2],q[:,1::2])
  return a[:,0],q[:,0]
def main():
  m=load_model();OUT.mkdir(parents=True,exist_ok=True);rng=np.random.default_rng(0xada);rows=8;h=128;eps=1e-5
  xb=m.float_to_bits(np.asarray(rng.normal(0.2,1.0,(rows,h)),np.float32));x=m.bits_to_float(xb)
  gb=m.float_to_bits(np.asarray(rng.uniform(0.5,1.5,(rows,h)),np.float32));g=m.bits_to_float(gb)
  bb=m.float_to_bits(np.asarray(rng.uniform(-0.4,0.4,(rows,h)),np.float32));b=m.bits_to_float(bb)
  total,sumsq=reduce(x);mean,inv=m.scalar_fp32(total,sumsq,h,eps,"FP32_NR2")
  mixed=m.float_to_bits(add(np.asarray(np.asarray(x-mean[:,None],np.float32)*inv[:,None],np.float32)*g,b))
  rm=np.mean(x,axis=1,dtype=np.float32);rv=np.mean(np.asarray((x-rm[:,None])**2,np.float32),axis=1,dtype=np.float32);ri=np.asarray(1/np.sqrt(rv+np.float32(eps)),np.float32)
  ref=m.float_to_bits(add(np.asarray(np.asarray(x-rm[:,None],np.float32)*ri[:,None],np.float32)*g,b))
  for n,v in (("x",xb.reshape(-1)),("gamma",gb.reshape(-1)),("beta",bb.reshape(-1)),("mixed_expected",mixed.reshape(-1)),("reference_expected",ref.reshape(-1))):write(OUT/f"adaln_w128_{n}.hex",v)
  err=np.abs(m.bits_to_float(mixed)-m.bits_to_float(ref));row={"profile_id":"adaln_w128","rows":rows,"hidden_size":h,"vectors_per_bank":1,"inv_hidden_fp32":f"{bits(1/h):08x}","epsilon_fp32":f"{bits(eps):08x}","max_abs":float(np.max(err)),"bit_mismatches":int(np.count_nonzero(mixed!=ref))}
  with(OUT/"accuracy.csv").open("w",newline="",encoding="utf-8")as f:w=csv.DictWriter(f,fieldnames=list(row));w.writeheader();w.writerow(row)
  if row["max_abs"]>0.025:raise SystemExit("AdaLayerNorm accuracy threshold exceeded")
  print(f"ADALAYERNORM_VECTORS PASS max_abs={row['max_abs']:.8f} mismatches={row['bit_mismatches']}")
if __name__=="__main__":main()
