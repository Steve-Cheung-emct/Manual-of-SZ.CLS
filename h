uplatex main-h.tex
ptex2pdf -l -u  -ot "-kanji=utf8 " main-h.tex
rm -f *.aux *.bak *.log *.bbl *.blg *.thm *.toc *.out *.lof *.lol *.lot *.ent *.fdb_latexmk *.synctex.gz

cd "/cygdrive/c/Program Files (x86)/Adobe/Acrobat 11.0/Acrobat"
./Acrobat.exe "C:\cygwin64\home\Cheung\sz\main-h.pdf"

