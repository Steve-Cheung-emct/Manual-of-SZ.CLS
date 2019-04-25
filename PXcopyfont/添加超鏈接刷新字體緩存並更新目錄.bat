fc-cache -f -r
cd C:\texlive\2018\texmf-dist\scripts\cjk-gs-integrate
perl cjk-gs-integrate.pl --link-texmf --force
mktexlsr
updmap-sys
pause