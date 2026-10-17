#!/bin/bash
# extract.sh <tech> : images du clip retournées (tori à gauche), 960x540, + planche numérotée
set -e
S=${ROTO:-/tmp/roto}
t=$1
mkdir -p $S/$t
ffmpeg -v error -y -i $(dirname "$0")/../../clips/$t.mp4 -vf "hflip,scale=960:540" -start_number 0 $S/$t/f%03d.png
python3 - "$S/$t" <<'PY'
import sys, glob
from PIL import Image, ImageDraw
d=sys.argv[1]
fs=sorted(glob.glob(d+'/f*.png'))
cols=8; w,h=240,135
rows=(len(fs)+cols-1)//cols
sheet=Image.new('RGB',(cols*w,rows*h))
dr=ImageDraw.Draw(sheet)
for i,f in enumerate(fs):
    im=Image.open(f).resize((w,h))
    sheet.paste(im,((i%cols)*w,(i//cols)*h))
    dr.rectangle([(i%cols)*w,(i//cols)*h,(i%cols)*w+26,(i//cols)*h+14],fill=(255,255,0))
    dr.text(((i%cols)*w+2,(i//cols)*h+1),str(i),fill=(0,0,0))
sheet.save(d+'_sheet.png')
print(len(fs),'images')
PY
